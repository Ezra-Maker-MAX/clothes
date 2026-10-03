/**
 * POST /api/private-verify —— 私密模式门禁验证
 *
 * 密码只存在 Vercel 环境变量 PRIVATE_MODE_PASSWORD 里，
 * 客户端代码与安装包里没有任何密码信息；本接口只回「对/不对」。
 *
 * 安全考量：
 * - timingSafeEqual 常时比较，防时序侧信道猜密码；
 * - 未配置环境变量时返回 503 明确提示（区别于密码错误，避免用户白猜）；
 * - 错误提示统一措辞，不泄露任何额外信息；
 * -🔒 失败计数 + 临时锁定：连续错5 次锁 15 分钟。没有这一步的话，
 *   4~6 位短密码在无速率限制下可被暴力枚举（Vercel 侧有免费额度保护，
 *   但额度耗尽只是变成 429，仍挡不住持续枚举）。
 *
 * ⚠️ 锁定状态存在 Serverless 实例内存里：实例被回收就失效。
 *    对「防随手乱试」这个目标够用（真正的强要求需接外部 KV，如 Upstash Redis）。
 *    私人自用场景下，攻击者要维持枚举必须持续打——实例回收反而会帮他重置，
 *    所以这里定位为「提高暴力成本」而非「绝对防护」。
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { timingSafeEqual } from 'node:crypto';
import { cors, ok, fail, clientIp } from '../lib/http';
import { issuePrivateToken } from '../lib/private-token';

/** 连续失败上限 */
const MAX_FAILS = 5;
/** 触发上限后的锁定时长 */
const LOCK_MS = 15 * 60_000;

/**
 * 按 IP 计数的失败记录。用Map 而不是对象，避免原型链键污染
 * （IP 来自请求头，不能当可信对象键直接往 {} 上挂）。
 */
const fails = new Map<string, { n: number; until: number }>();

function now(): number {
  return Date.now();
}

/** 顺带清理过期条目，防止 Map 无限增长（Serverless 长驻实例内存有限） */
function sweep(): void {
  if (fails.size < 64) return;
  const t = now();
  for (const [k, v] of fails) if (v.until < t) fails.delete(k);
}

function lockRemaining(key: string): number {
  const rec = fails.get(key);
  if (!rec || rec.until <= now()) return 0;
  return Math.ceil((rec.until - now()) / 1000);
}

export async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);
  if (req.method !== 'POST') return fail(res, 405, '仅支持 POST');

  const expected = (process.env.PRIVATE_MODE_PASSWORD ?? '').trim();
  if (!expected) {
    return fail(
      res,
      503,
      '服务端尚未配置私密模式密码：请在 Vercel 环境变量中设置 PRIVATE_MODE_PASSWORD，配置后需 Redeploy 生效',
    );
  }

  // 锁定检查放在读 body 之前：被锁时连密码都不必解析
  sweep();
  const key = clientIp(req) || 'unknown';
  const locked = lockRemaining(key);
  if (locked > 0) {
    return fail(res, 429, `密码错误次数过多，请 ${Math.ceil(locked / 60)} 分钟后再试`);
  }

  let given = '';
  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body ?? {});
    given = String(body?.password ?? '');
  } catch {
    return fail(res, 400, '请求体格式有误');
  }

  // 常时比较：长度不同直接不等；等长才逐字节比（timingSafeEqual 要求等长 Buffer）
  const a = Buffer.from(expected, 'utf8');
  const b = Buffer.from(given, 'utf8');
  const same = a.length === b.length && timingSafeEqual(a, b);

  if (!same) {
    const rec = fails.get(key) ?? { n: 0, until: 0 };
    rec.n += 1;
    if (rec.n >= MAX_FAILS) rec.until = now() + LOCK_MS;
    fails.set(key, rec);
    const left = MAX_FAILS - rec.n;
    // 前几次给出「还剩几次」纯属自用体验优化；一旦锁定就不再报剩余次数，
    // 避免变成一个「密码还差几次」的引导器
    return left > 0
      ? fail(res, 401, `密码不对，还可尝试 ${left} 次`)
      : fail(res, 429, `密码错误次数过多，请 ${MAX_FAILS * 3} 分钟后再试`);
  }

  // 校验通过：清空该 IP 的失败记录（否则下次连错一次又会从上限开始算）
  fails.delete(key);

  // 颁发数据接口令牌：私密空间数据（围度/肤色/部位图/相册）与私密图取流都验它
  return ok(res, { unlocked: true, token: issuePrivateToken() });
}
