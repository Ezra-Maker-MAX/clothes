/**
 * GET /api/private-image —— 私密图取流代理（鉴权 + 私有 store 凭据在此收口）
 *
 * 为什么需要这个接口：私密图存在 access=private 的 Vercel Blob store 里，
 * 它的 URL 对匿名请求直接 403。这是**正确**的行为——但意味着客户端不能像
 * 衣橱图那样直接 `Image.network(blobUrl)`。于是本接口负责：
 *   验会话令牌（/api/private-verify 颁发的 HMAC token）→  用服务端凭据
 *   get(blob, access:'private') 取流 → 回给客户端显示。
 *
 * 关键安全属性：
 * - 令牌走 Authorization header，**不放 query**（query 会进浏览器历史/日志）；
 * - pathname 白名单校验：只允许 private/ 前缀，且拒绝含 `..` 的路径，
 *   防止拿这个接口当任意文件读取器去读公开 store 里的其他对象；
 * - 返回体走 `Content-Disposition: inline` + `X-Content-Type-Options: nosniff`，
 *   不给任何缓存留副本（私密照片不该出现在设备磁盘缓存里）。
 *
 * 缓存策略：私密图默认 `no-store`。用户替换图片后同一 pathname 会变（带 uuid），
 * 所以不存在陈旧缓存问题；不需要 CDN 缓存，也就不需要 presign 的过期管理。
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { get } from '@vercel/blob';
import { cors, fail } from '../lib/http';
import { verifyPrivateToken, tokenOf } from '../lib/private-token';
import { privateBlobConfigured, privateBlobAuth, PRIVATE_BLOB_SETUP_HINT } from '../lib/blob';

/** 只允许读 private/ 前缀，且不接受任何路径穿越 */
function safePathname(raw: unknown): string | null {
  const p = String(raw ?? '');
  if (!p) return null;
  if (p.includes('..') || p.includes('//') || p.startsWith('/')) return null;
  if (!p.startsWith('private/')) return null;
  return p;
}

export async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);
  if (req.method !== 'GET') return fail(res, 405, '仅支持 GET');

  if (!verifyPrivateToken(tokenOf(req))) {
    return fail(res, 401, '私密空间会话无效或已过期，请重新输密码解锁');
  }
  if (!privateBlobConfigured()) {
    return fail(res, 503, PRIVATE_BLOB_SETUP_HINT);
  }

  const pathname = safePathname(req.query?.pathname);
  if (!pathname) {
    return fail(res, 400, 'pathname 非法（仅允许 private/ 前缀的合法路径）');
  }

  try {
    const r = await get(pathname, { access: 'private', ...privateBlobAuth() });
    if (!r || r.statusCode !== 200 || !r.stream) {
      return fail(res, 404, '图片不存在');
    }
    res.setHeader('Content-Type', r.blob.contentType || 'image/jpeg');
    // 私密图不留缓存副本
    res.setHeader('Cache-Control', 'private, no-store, max-age=0');
    res.setHeader('Content-Disposition', 'inline');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const reader = r.stream.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      // VercelResponse 底层是 Node ServerResponse，可直接写 ReadableStream chunk
      (res as unknown as { write: (c: Uint8Array) => boolean }).write(value);
    }
    return (res as unknown as { end: () => void }).end();
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    // 404（对象不存在）与 403（凭据不对）分开报，便于用户定位是配置问题还是数据问题
    if (/not found|404|does not exist/i.test(msg)) return fail(res, 404, '图片不存在');
    console.warn('[private-image] 取流失败：', msg.slice(0, 200));
    return fail(res, 500, '私密图读取失败，稍后再试');
  }
}
