/**
 * /api/[action] —— 统一 API 入口（单函数动态路由）
 *
 * 为什么合并：Vercel Hobby 计划限制「每个部署最多 12 个 serverless functions」，
 * api/ 顶层每文件一个函数（连 lib/ 共享文件也被计入配额），加一个接口就超限。
 * 合并为单函数 + 内部路由表后函数数恒为 1，且 URL 路径完全不变（客户端零改动）。
 *
 * 约定：
 * - 业务逻辑全部在 api/_handlers/（下划线开头目录不计函数配额），
 *   每个模块 `export async function handler(req, res)`，方法内自判 GET/POST/PATCH/DELETE；
 * - 新增接口两步：_handlers/ 加模块 + 下方 routes 注册一行；
 * - 访问路径不变：/api/recommend、/api/wardrobe、/api/health …
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { cors, fail } from './_lib/http';
import * as recommend from './_handlers/recommend';
import * as wardrobe from './_handlers/wardrobe';
import * as categories from './_handlers/categories';
import * as history from './_handlers/history';
import * as upload from './_handlers/upload';
import * as importOrder from './_handlers/import-order';
import * as health from './_handlers/health';

type Handler = (req: VercelRequest, res: VercelResponse) => Promise<unknown> | unknown;

const routes: Record<string, Handler> = {
  recommend: recommend.handler,
  wardrobe: wardrobe.handler,
  categories: categories.handler,
  history: history.handler,
  upload: upload.handler,
  'import-order': importOrder.handler,
  health: health.handler,
};

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // preflight 统一处理（各业务 handler 里的 cors() 对真实请求继续生效）
  cors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();

  const action = String(req.query.action ?? '').toLowerCase();
  const h = routes[action];
  if (!h) return fail(res, 404, `未知接口 /api/${action}`);
  try {
    return await h(req, res);
  } catch (e) {
    // 兜底：任何未捕获异常统一 500，避免函数裸崩
    return fail(res, 500, '服务开小差了', e instanceof Error ? e.message : String(e));
  }
}
