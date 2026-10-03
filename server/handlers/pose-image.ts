/**
 * GET /api/pose-image —— 姿势参考图取流代理
 *
 * 为什么需要这个接口：姿势图存在 access=private 的 Blob store 里，
 * 它的 URL 对匿名请求直接 403（这是**正确**的行为）。而 App 侧试衣请求
 * 是手机直连用户自部署的模型服务、刻意不过 Vercel（隐私隔离），
 * 所以姿势图只能由本接口转发给 App 展示。
 *
 * 与 /api/private-image 的区别（重要，不是重复代码）：
 * - private-image服务的是**用户自己的身体部位图/私密相册**，
 *   那是真正的敏感数据，必须验私密会话令牌（HMAC，绑定密码）；
 * - 姿势图是公共参考素材（第三方骨骼模型图），本身不含用户隐私，
 *   所以**不要求私密令牌**，只做 pathname 白名单限制。
 *   门槛放在别处：公共图片接口仍要求 PRIVATE_BLOB_STORE_ID/token存在
 *   （未配置就 503），避免变成任何人都能随便代理读你 store 里的东西。
 *
 * 路径白名单只放行 poses/ 前缀 + 严格的文件名形态：
 *   ^poses/\d{7}_\d{5}\.webp$
 * 拒绝 `..`、`//`、绝对路径、以及任何试图读到 poses/ 之外的输入——
 * 否则这个接口就成了「读你整个 store 的任意文件」的漏洞。
 *
 * 缓存：姿势图是**内容不变**的静态素材（文件名由 poseId+modelId 决定），
 * 与私密照片的 no-store 策略相反，这里允许 CDN/客户端长期缓存
 * （immutable, max-age=1 年），否则 205 张图每次打开姿势库都要重下。
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { get } from '@vercel/blob';
import { cors, fail } from '../lib/http';
import { privateBlobConfigured, privateBlobAuth, PRIVATE_BLOB_SETUP_HINT } from '../lib/blob';

/**
 * 姿势图 pathname 白名单。
 *
 * 为什么用「严格正则」而不是 private-image 那种「前缀匹配」：
 * 前缀匹配 `startsWith('poses/')` 会允许 `poses/../../private/x.webp` 这类
 * 构造（`..` 虽然被拦了，但一旦漏一处就是越权读整个 store）。
 * 这里锁死完整形态：目录 + 7 位 poseId + 5 位 modelId + .webp，
 * 多余字符一律拒绝。文件名由上传脚本生成（见 scripts/upload-poses.mjs），
 * 形态是确定的，不需要更宽松的规则。
 */
const POSE_PATHNAME = /^poses\/\d{7}_\d{5}\.webp$/;

function safePathname(raw: unknown): string | null {
  const p = String(raw ?? '');
  if (!p) return null;
  if (p.includes('..') || p.includes('//') || p.startsWith('/')) return null;
  if (p.includes('\\') || p.includes('..')) return null;
  return POSE_PATHNAME.test(p) ? p : null;
}

export async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);
  if (req.method !== 'GET') return fail(res, 405, '仅支持 GET');

  const pathname = safePathname(req.query?.pathname);
  if (!pathname) {
    return fail(res, 400, 'pathname 非法（姿势图只允许 poses/<poseId>_<modelId>.webp 形态）');
  }

  // 没配私密 store 就明确 503，绝不回退到公开 store 去取——
  // 回退会让姿势图落到公开 URL，那正是这次改造要避免的。
  if (!privateBlobConfigured()) {
    return fail(res, 503, PRIVATE_BLOB_SETUP_HINT);
  }

  try {
    const r = await get(pathname, { access: 'private', ...privateBlobAuth() });
    if (!r || r.statusCode !== 200 || !r.stream) {
      return fail(res, 404, '姿势图不存在，先跑 scripts/upload-poses.mjs 导入');
    }
    res.setHeader('Content-Type', r.blob.contentType || 'image/webp');
    // 姿势图内容与文件名绑定（不可变），允许长期缓存，避免每次进姿势库重下205 张
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    res.setHeader('Content-Disposition', 'inline');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const reader = r.stream.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      (res as unknown as { write: (c: Uint8Array) => boolean }).write(value);
    }
    return (res as unknown as { end: () => void }).end();
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (/not found|404|does not exist/i.test(msg)) {
      return fail(res, 404, '姿势图不存在，先跑 scripts/upload-poses.mjs 导入');
    }
    if (/BLOB_STORE_ID|BLOB_READ_WRITE_TOKEN|No token|oidc|forbidden|403/i.test(msg)) {
      return fail(res, 503, '私密存储凭据不可用：' + PRIVATE_BLOB_SETUP_HINT);
    }
    console.warn('[pose-image] 取流失败：', msg.slice(0, 200));
    return fail(res, 500, '姿势图读取失败，稍后再试');
  }
}