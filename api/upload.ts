/**
 * /api/upload —— 衣橱单品图片上传（Vercel Blob）
 *
 * POST body(JSON): { filename, contentType, dataBase64 }
 *   → 返回 { url }，Flutter 端拿到后调 POST /api/wardrobe 落库
 *
 * ⚠️ 环境变量：BLOB_READ_WRITE_TOKEN
 *   在 Vercel 项目 → Storage → Create Blob Store → Connect，会自动注入，
 *   本地 vercel dev 会在 vercel env pull 后可用。
 *
 * 为什么选 Vercel Blob 而不是先上 Cloudinary：
 *   零配置、同平台计费、SDK 一行搞定；Cloudinary 的图片处理/抠图
 *   作为第二阶段增强（见 docs/03-图片存储方案.md），接口签名已预留。
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { put } from '@vercel/blob';
import { cors, ok, fail } from './lib/http';
import { uuid } from './lib/db';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);

  if (req.method === 'GET') {
    // 状态自检：让前端/浏览器能快速判断存储是否就绪
    return ok(res, {
      storage: 'vercel-blob',
      ready: Boolean(process.env.BLOB_READ_WRITE_TOKEN),
      hint: process.env.BLOB_READ_WRITE_TOKEN
        ? 'Blob 已就绪'
        : '缺少 BLOB_READ_WRITE_TOKEN：在 Vercel → Storage → Blob 创建并连接后自动注入',
    });
  }

  if (req.method !== 'POST') return fail(res, 405, `不支持的请求方法: ${req.method}`);

  const b = req.body ?? {};
  if (!b.filename || !b.dataBase64) return fail(res, 400, 'filename 与 dataBase64 必填');

  try {
    const buf = Buffer.from(String(b.dataBase64), 'base64');
    if (buf.length > 8 * 1024 * 1024) return fail(res, 413, '图片超过 8MB，先压缩再传');

    const safeName = String(b.filename).replace(/[^\w.-]/g, '_');
    const blob = await put(`wardrobe/${uuid()}-${safeName}`, buf, {
      access: 'public',
      contentType: String(b.contentType ?? 'image/jpeg'),
      addRandomSuffix: false,
    });

    // 后续接抠图 API 的挂载点：blob.url → 第三方抠图 → 回写 thumbnail_url
    return ok(res, { url: blob.url, size: buf.length });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const hint = msg.includes('BLOB_READ_WRITE_TOKEN') || msg.includes('No token')
      ? '未配置 BLOB_READ_WRITE_TOKEN，去 Vercel → Storage 创建 Blob Store 并连接项目'
      : '上传失败';
    return fail(res, 500, hint, msg);
  }
}
