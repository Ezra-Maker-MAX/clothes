/**
 * /api —— 统一 API 入口（单函数动态路由，全项目唯一 Serverless Function）
 *
 * 为什么合并：Vercel Hobby 计划限制「每个部署最多 12 个 serverless functions」，
 * 且实测 api/ 目录下【每个 .ts 文件都占一个函数名额】——包括没有 handler 的
 * 共享库文件，`_` 前缀目录也不豁免。
 * 双保险措施：
 * 1) 业务代码全部移到 api/ 之外的 server/（handlers + lib），api/ 里只剩本文件；
 * 2) vercel.json 改用显式 builds 声明（官方语义：只构建列出的文件），
 *    仓库里即使残留历史 api/*.ts 文件也不会被部署为函数。
 * 普通模块经 import 打进函数 bundle，URL 路径完全不变（客户端零改动）。
 *
 * 约定：
 * - 业务逻辑全部在 server/handlers/，每个模块
 *   `export async function handler(req, res)`，方法内自判 GET/POST/PATCH/DELETE；
 * - 新增接口两步：server/handlers/ 加模块 + 下方 routes 注册一行；
 * - 访问路径不变：/api?action=health / wardrobe / recommend …
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { cors, fail } from '../server/lib/http';
import * as recommend from '../server/handlers/recommend';
import * as wardrobe from '../server/handlers/wardrobe';
import * as categories from '../server/handlers/categories';
import * as history from '../server/handlers/history';
import * as upload from '../server/handlers/upload';
import * as importOrder from '../server/handlers/import-order';
import * as health from '../server/handlers/health';

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

  const action = resolveAction(req);
  const h = routes[action];
  if (!h) return fail(res, 404, `未知接口 /api/${action}`);
  try {
    return await h(req, res);
  } catch (e) {
    // 兜底：任何未捕获异常统一 500，避免函数裸崩
    return fail(res, 500, '服务开小差了', e instanceof Error ? e.message : String(e));
  }
}

/**
 * 解析接口名，双格式兼容：
 * 1) 路径形式 /api/health（App 端实际使用，vercel.json routes 会注入 ?action=，
 *    此处兜底直接从 URL 解析，routes 注入行为万一变化也不受影响）；
 * 2) 查询形式 /api?action=health（浏览器自检/手动测试用）。
 */
function resolveAction(req: VercelRequest): string {
  const q = String(req.query.action ?? '').toLowerCase();
  if (q) return q;
  const m = /^\/api\/([^/?#]+)/.exec(String(req.url ?? ''));
  const seg = m?.[1] ?? '';
  // routes 重写后 url 若变成 /api/gateway.ts 自身，不算接口名
  return seg === 'gateway.ts' ? '' : decodeURIComponent(seg).toLowerCase();
}
