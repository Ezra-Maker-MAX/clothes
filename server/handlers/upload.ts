/**
 * /api/upload —— 衣橱单品图片上传（Vercel Blob）
 *
 * POST body(JSON): { filename, contentType, dataBase64 }
 *   → 返回 { url, cutoutUrl? }，Flutter 端拿到后调 POST /api/wardrobe 落库
 *
 * AI 抠图挂载点（已接通，env 可选配置，未配置/失败一律静默降级为原图，绝不阻断上传）：
 *   REMBG_API_URL     通用自部署抠图端点：POST 图片二进制 → 返回透明 PNG 二进制
 *   REMOVE_BG_API_KEY remove.bg 官方 API Key（https://www.remove.bg/dashboard#api-key）
 *   两者都配时优先 REMBG_API_URL（自有服务优先，省第三方额度）
 *
 * ⚠️ 环境变量（两种认证模式，二选一即可）：
 *   A. OIDC（Vercel 官方推荐）：Dashboard → Storage → Create Blob Store(access=Public)
 *      → Connect to Project，Vercel 自动注入 BLOB_STORE_ID + OIDC 凭证，**无需任何手写token**
 *   B. 长效token：Store → Tokens → Create Token（勾 Public Access）
 *      →手动加 BLOB_READ_WRITE_TOKEN（代码外部运行/client upload 才需要）
 *   判定入口统一走 blobReady()，两种模式都能识别；本地需 vercel link && vercel env pull .env
 *
 * 为什么选 Vercel Blob 而不是先上 Cloudinary：
 *   零配置、同平台计费、SDK 一行搞定；Cloudinary 的图片处理/抠图
 *   作为第二阶段增强（见 docs/03-图片存储方案.md），接口签名已预留。
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { put } from '@vercel/blob';
import { cors, ok, fail } from '../lib/http';
import { uuid } from '../lib/db';
import { probeBlob, blobAuthMode } from '../lib/blob';

/** 抠图超时：8s 拿不到就当没有，主链路（原图）早已落 Blob 成功 */
const CUTOUT_TIMEOUT_MS = 8000;

/** 调抠图服务返回透明 PNG；任何失败返回 null（调用方降级原图） */
async function cutout(buf: Buffer): Promise<Buffer | null> {
  try {
    let r: Response;
    if (process.env.REMBG_API_URL) {
      // 通用自部署端点：POST bytes → PNG bytes
      r = await fetch(process.env.REMBG_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/octet-stream' },
        body: new Uint8Array(buf),
        signal: AbortSignal.timeout(CUTOUT_TIMEOUT_MS),
      });
    } else if (process.env.REMOVE_BG_API_KEY) {
      // remove.bg 官方 API（multipart form）
      const form = new FormData();
      form.append('image_file', new Blob([new Uint8Array(buf)]), 'image.jpg');
      form.append('size', 'auto');
      r = await fetch('https://api.remove.bg/v1.0/removebg', {
        method: 'POST',
        headers: { 'X-Api-Key': process.env.REMOVE_BG_API_KEY },
        body: form,
        signal: AbortSignal.timeout(CUTOUT_TIMEOUT_MS),
      });
    } else {
      return null; // 未配置 → 抠图关闭，原图直出
    }
    if (!r.ok) {
      console.warn('[upload] 抠图失败（降级原图）：HTTP', r.status);
      return null;
    }
    const out = Buffer.from(await r.arrayBuffer());
    // 透明 PNG 至少不会小于几 KB；异常小体积极可能是错误页
    return out.length > 1024 ? out : null;
  } catch (e) {
    console.warn('[upload] 抠图异常（降级原图）：', e instanceof Error ? e.message : e);
    return null;
  }
}

export async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);

  if (req.method === 'GET') {
    // 状态自检：让前端/浏览器能快速判断存储与抠图是否就绪
    const cutoutProvider = process.env.REMBG_API_URL
      ? 'self-hosted (REMBG_API_URL)'
      : process.env.REMOVE_BG_API_KEY
        ? 'remove.bg'
        : null;
    const blob = await probeBlob();
    return ok(res, {
      storage: 'vercel-blob',
      ready: blob.ready,
      authMode: blobAuthMode(),
      detail: blob.detail,
      hint: blob.ready
        ? 'Blob 已就绪，可直接上传'
        : blob.detail,
      cutout: {
        ready: Boolean(cutoutProvider),
        provider: cutoutProvider,
        hint: cutoutProvider ? '抠图已开启，失败自动降级原图' : '未配置抠图（可选）：设 REMBG_API_URL 或 REMOVE_BG_API_KEY',
      },
    });
  }

  if (req.method !== 'POST') return fail(res, 405, `不支持的请求方法: ${req.method}`);

  const b = req.body ?? {};
  if (!b.filename || !b.dataBase64) return fail(res, 400, 'filename 与 dataBase64 必填');

  try {
    const buf = Buffer.from(String(b.dataBase64), 'base64');
    // ⚠️ Vercel Serverless Function 请求体硬上限 4.5MB（Hobby 计划不可调），
    // 且 base64 会让体积膨胀约 33% → 原始图片必须 ≤3MB。
    // 客户端（image_picker 原生压缩）已保证，这里是兜底：真收到超限请求，
    // 说明客户端还是旧版（file_picker 在 Android 不压缩），提示升级而不是含糊报错。
    if (buf.length > 3 * 1024 * 1024)
      return fail(res, 413, '图片超过 3MB，请用最新版 App 上传（新版会自动压缩）');

    const safeName = String(b.filename).replace(/[^\w.-]/g, '_');
    const blob = await put(`wardrobe/${uuid()}-${safeName}`, buf, {
      access: 'public',
      contentType: String(b.contentType ?? 'image/jpeg'),
      addRandomSuffix: false,
    });

    // AI 抠图：成功则把透明 PNG 也落 Blob（原 blob.url 已在手，失败静默降级）
    let cutoutUrl: string | null = null;
    const cut = await cutout(buf);
    if (cut) {
      const cutBlob = await put(`wardrobe/${uuid()}-cutout.png`, cut, {
        access: 'public',
        contentType: 'image/png',
        addRandomSuffix: false,
      });
      cutoutUrl = cutBlob.url;
    }

    return ok(res, { url: blob.url, cutoutUrl, size: buf.length });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    // 判定要覆盖 OIDC 与 token 两种模式的报错措辞，否则改成 OIDC 后提示会指向错误方向
    const noAuth = /BLOB_READ_WRITE_TOKEN|BLOB_STORE_ID|No token|missing token|oidc/i.test(msg);
    const blocked = /suspend|blocked/i.test(msg);
    const hint = noAuth
      ? (blocked
        ? 'Blob store 被 Vercel 封停（多半是 Hobby 用量超限）。代码侧无解，请提 Vercel Support 工单恢复。'
        : '未连接 Blob store：Vercel → Storage → Create Blob Store（access 选 Public）→ Connect to Project')
      : blocked
        ? 'Blob store 被 Vercel 封停，请在 Storage → Store 详情看用量是否超限，超了只能提工单。'
        : '上传失败';
    return fail(res, 500, hint, msg);
  }
}
