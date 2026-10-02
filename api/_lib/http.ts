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
