/**
 * /api/private-profile —— 私密空间数据（围度 / 肤色 / 部位图 / 私密相册）
 *
 * 鉴权：Authorization: Bearer <token>（/api/private-verify 颁发，HMAC 绑定
 *       PRIVATE_MODE_PASSWORD）。token 无效 → 401，数据绝不能匿名读写。
 * 存储：Turso private_profile 表（user_id 主键，body/photos 两列 JSON）。
 *
 * 🔒 photos 里存的是**私密 blob 的 pathname**，不是 URL。私有 blob 的 URL
 *    匿名访问 403，存 URL 没有意义，且极易被误当成「可直连公开地址」泄漏；
 *    展示请走 /api/private-image 代理（验 token + 服务端带凭据取流）。
 *
 * GET → { body: {...}, photos: [...] }   没存过 → 空结构
 * PUT ← { body?: object, photos?: array } 全量覆盖保存（App 端持全量，协议最简）
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { cors, ok, fail, clientIp } from '../lib/http';
import { getDb, ensureSchema } from '../lib/db';
import { verifyPrivateToken, tokenOf } from '../lib/private-token';

/**
 * 私密空间的唯一 owner id。
 *
 * 原来这里硬编码 'private_demo'、衣橱侧硬编码 'u_demo_0001'，两套 id 不一致，
 * 多用户时必炸。现在统一到常量：真要上多用户，只需把PRIVATE_USER_ID 换成
 * 从 token payload 里解出的用户 id（private-token.ts 的签名域已包含 userId 位）。
 */
const PRIVATE_USER_ID = process.env.PRIVATE_USER_ID?.trim() || 'u_demo_0001';


export async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);
  if (req.method !== 'GET' && req.method !== 'PUT') {
    return fail(res, 405, '仅支持 GET / PUT');
  }

  // ---- 鉴权 ----
  const token = tokenOf(req);
  if (!verifyPrivateToken(token)) {
    return fail(res, 401, '私密空间会话无效或已过期，请重新输密码解锁');
  }

  const db = getDb();
  if (!db) {
    return fail(res, 503, '数据库未配置（TURSO_URL / TURSO_AUTH_TOKEN），私密数据云端暂不可用');
  }
  await ensureSchema();

  const userId = PRIVATE_USER_ID;
  try {
    if (req.method === 'GET') {
      const r = await db.execute({
        sql: 'SELECT body, photos FROM private_profile WHERE user_id = ?',
        args: [userId],
      });
      const row = r.rows[0];
      if (!row) return ok(res, { body: {}, photos: [] });
      let body: unknown = {};
      let photos: unknown = [];
      try {
        body = JSON.parse(String(row.body ?? '{}'));
      } catch { /* 容错：坏数据按空处理 */ }
      try {
        photos = JSON.parse(String(row.photos ?? '[]'));
      } catch { /* 同上 */ }
      return ok(res, { body, photos });
    }

    // ---- PUT：全量覆盖 ----
    const b = (req.body ?? {}) as { body?: unknown; photos?: unknown };
    const bodyJson = JSON.stringify(b.body ?? {});
    const photosJson = JSON.stringify(Array.isArray(b.photos) ? b.photos : []);
    if (bodyJson.length > 256_000 || photosJson.length > 256_000) {
      return fail(res, 413, '私密数据体积超限（>256KB），检查照片数量是否异常');
    }
    await db.execute({
      sql: `INSERT INTO private_profile (user_id, body, photos, updated_at)
            VALUES (?, ?, ?, datetime('now'))
            ON CONFLICT(user_id) DO UPDATE
            SET body = excluded.body, photos = excluded.photos,
                updated_at = datetime('now')`,
      args: [userId, bodyJson, photosJson],
    });
    return ok(res, { saved: true, at: new Date().toISOString() });
  } catch (e) {
    // 只记错误信息与调用方来源，不掺 uuid：uuid 让排查的人每次都要先分辨
    // 哪个是标识哪个是错误，真正的错误信息反而被噪音淹没
    console.warn('[private-profile] 失败：', e instanceof Error ? e.message : e, 'ip=' + clientIp(req));
    return fail(res, 500, '私密数据读写失败，稍后再试');
  }
}
