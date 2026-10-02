/**
 * HTTP 响应小工具：统一 JSON 结构 + CORS（Flutter Web 跨端调用必需）
 */
import type { VercelResponse, VercelRequest } from '@vercel/node';

export function cors(req: VercelRequest, res: VercelResponse): void {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
}

export function ok(res: VercelResponse, data: unknown): void {
  res.status(200).json({ ok: true, data });
}

export function fail(res: VercelResponse, code: number, message: string, extra?: unknown): void {
  res.status(code).json({ ok: false, error: message, detail: extra ?? null });
}

/**
 * 取访问者真实 IP（用于天气自动定位）。
 * Vercel 优先 x-vercel-forwarded-for，其次 x-forwarded-for / x-real-ip；
 * 本地 vercel dev / pnpm local 没有这些头，返回空串（跳过定位）。
 */
export function clientIp(req: VercelRequest): string {
  const pick = (v: string | string[] | undefined): string =>
    (Array.isArray(v) ? v[0] : v ?? '').split(',')[0]?.trim() ?? '';
  const h = req.headers ?? {};
  return pick(h['x-vercel-forwarded-for'] as string | undefined) ||
    pick(h['x-forwarded-for'] as string | undefined) ||
    pick(h['x-real-ip'] as string | undefined);
}
