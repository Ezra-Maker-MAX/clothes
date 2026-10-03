/**
 * 私密数据接口的会话令牌（HMAC 绑定 PRIVATE_MODE_PASSWORD）
 *
 * 为什么需要：私密空间的数据接口（/api/private-profile）存的是身体围度、
 * 肤色、部位图与私密照片，绝不能匿名可读写。App 无登录体系，所以用
 * 「密码验证通过 → 服务端颁发 HMAC token → 数据接口验 token」的最小方案：
 *   - token = <过期时间戳>.<HMAC-SHA256(密码, "private|<时间戳>")>
 *   - 密码只存在环境变量里，token 无法伪造；过期即失效
 *   - 用户改密码（换环境变量值）= 所有旧 token 立刻全部失效
 */
import { createHmac, timingSafeEqual } from 'node:crypto';

const SECRET = (): string => (process.env.PRIVATE_MODE_PASSWORD ?? '').trim();

/** 颁发 token，默认 7 天有效（客户端 24h 内免输密码，自己管体验） */
export function issuePrivateToken(validHours = 168): string | null {
  const secret = SECRET();
  if (!secret) return null;
  const exp = Date.now() + validHours * 3600_000;
  const sig = createHmac('sha256', secret).update(`private|${exp}`).digest('hex');
  return `${exp}.${sig}`;
}

/** 校验 token：未过期 + HMAC 一致（常时比较，防时序侧信道） */
export function verifyPrivateToken(token: string | undefined | null): boolean {
  const secret = SECRET();
  if (!secret || !token) return false;
  const dot = token.indexOf('.');
  if (dot <= 0) return false;
  const exp = Number(token.slice(0, dot));
  const sig = token.slice(dot + 1);
  if (!Number.isFinite(exp) || exp < Date.now()) return false;
  const expect = createHmac('sha256', secret).update(`private|${exp}`).digest('hex');
  const a = Buffer.from(sig, 'utf8');
  const b = Buffer.from(expect, 'utf8');
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * 从请求里取令牌：`Authorization: Bearer <token>` 优先，
 * 退回请求体 token 字段（Event Handler 解析 body 早于 header 的场景）。
 *
 * ⚠️ 不要把它放在 URL query 上——query 会被浏览器历史/日志/Referer 记录，
 * 等于把令牌泄露出去。当前所有调用方都走 header 或 body。
 */
export function tokenOf(req: { headers?: Record<string, unknown>; body?: unknown }): string {
  const h = (req.headers?.authorization ?? '') as string;
  if (h.toLowerCase().startsWith('bearer ')) return h.slice(7).trim();
  return String((req.body as { token?: string })?.token ?? '');
}
