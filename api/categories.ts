/**
 * /api/categories —— 动态分类（衣橱 tab 展示层，与推荐引擎解耦）
 *
 * 设计：item.category 存分类 id。内置 7 行 id = 引擎 key（tops/bottoms/...），
 * 旧数据与内置行天然兼容；用户新建分类 id = uuid，通过 engine_key 映射引擎
 * 适配类别（recommend.ts 读衣橱后统一翻译）→ 引擎永不失明。
 *
 * GET    ?userId=xxx                     列表（按 sort_order；为空时 seed 内置 7 行）
 * POST   body: { userId, name, engineKey }   新建自定义分类（排到末尾）
 * PATCH  body: { userId, order: [ids] }      整体重排；或 { id, name } 重命名
 * DELETE ?id=xxx                         删除（内置/分类下仍有单品时拒绝）
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getDb, uuid, ensureSchema } from './lib/db';
import { cors, ok, fail } from './lib/http';

/** 内置分类：id 即引擎适配 key（旧 wardrobe_items.category 值天然兼容） */
const BUILTIN: Array<{ id: string; name: string }> = [
  { id: 'tops', name: '上衣' },
  { id: 'bottoms', name: '裤装' },
  { id: 'dresses', name: '裙装' },
  { id: 'outerwear', name: '外套' },
  { id: 'shoes', name: '鞋子' },
  { id: 'bags', name: '包包' },
  { id: 'accessories', name: '配饰' },
];

export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);
  const db = getDb();

  if (!db) {
    // mock：与内置 seed 同构（客户端 fallback 亦是这份）
    return ok(res, {
      mode: 'mock',
      items: BUILTIN.map((b, i) => ({
        id: b.id, name: b.name, engineKey: b.id, sortOrder: i + 1, isBuiltin: true,
      })),
    });
  }

  try {
    await ensureSchema();

    const seed = async (userId: string) => {
      const stmts = BUILTIN.map((b, i) => ({
        sql: `INSERT INTO categories (id, user_id, name, engine_key, sort_order, is_builtin)
              VALUES (?,?,?,?,?,1)`,
        args: [b.id, userId, b.name, b.id, i + 1],
      }));
      await db.batch(stmts, 'write');
    };

    // ---------- GET ----------
    if (req.method === 'GET') {
      const userId = String(req.query.userId ?? '');
      if (!userId) return fail(res, 400, '缺少 userId');
      const rows = await db.execute({
        sql: `SELECT * FROM categories WHERE user_id = ? ORDER BY sort_order, created_at`,
        args: [userId],
      });
      if (!rows.rows.length) {
        await seed(userId); // 首次访问 seed 内置 7 分类
        const fresh = await db.execute({
          sql: `SELECT * FROM categories WHERE user_id = ? ORDER BY sort_order`,
          args: [userId],
        });
        rows.rows = fresh.rows;
      }
      const items = (rows.rows as Array<Record<string, unknown>>).map((r) => ({
        id: String(r.id),
        name: String(r.name),
        engineKey: String(r.engine_key),
        sortOrder: Number(r.sort_order ?? 0),
        isBuiltin: Number(r.is_builtin ?? 0) === 1,
      }));
      return ok(res, { items });
    }

    // ---------- POST：新建（映射引擎类别） ----------
    if (req.method === 'POST') {
      const b = req.body ?? {};
      if (!b.userId || !b.name || !b.engineKey) return fail(res, 400, 'userId / name / engineKey 均为必填');
      const maxRow = await db.execute({
        sql: `SELECT COALESCE(MAX(sort_order), 0) AS m FROM categories WHERE user_id = ?`,
        args: [b.userId],
      });
      const nextSort = Number((maxRow.rows[0] as { m?: number } | undefined)?.m ?? 0) + 1;
      const id = uuid();
      await db.execute({
        sql: `INSERT INTO categories (id, user_id, name, engine_key, sort_order, is_builtin)
              VALUES (?,?,?,?,?,0)`,
        args: [id, b.userId, String(b.name).slice(0, 12), b.engineKey, nextSort],
      });
      return ok(res, { id });
    }

    // ---------- PATCH：整体重排 / 重命名 ----------
    if (req.method === 'PATCH') {
      const b = req.body ?? {};
      if (Array.isArray(b.order) && b.order.length) {
        await db.batch(b.order.map((id: string, i: number) => ({
          sql: `UPDATE categories SET sort_order = ? WHERE id = ?`,
          args: [i + 1, String(id)],
        })), 'write');
        return ok(res, { reordered: b.order.length });
      }
      if (b.id && b.name) {
        await db.execute({
          sql: `UPDATE categories SET name = ? WHERE id = ?`,
          args: [String(b.name).slice(0, 12), String(b.id)],
        });
        return ok(res, { id: b.id, renamed: true });
      }
      return fail(res, 400, '需要 order 数组（重排）或 id + name（重命名）');
    }

    // ---------- DELETE ----------
    if (req.method === 'DELETE') {
      const id = String(req.query.id ?? '');
      const userId = String(req.query.userId ?? '');
      if (!id || !userId) return fail(res, 400, '缺少 id / userId');
      const row = await db.execute({
        sql: `SELECT is_builtin FROM categories WHERE id = ? AND user_id = ?`,
        args: [id, userId],
      });
      if (!row.rows.length) return fail(res, 404, '分类不存在');
      if (Number((row.rows[0] as { is_builtin?: number }).is_builtin) === 1) {
        return fail(res, 400, '内置分类不能删除');
      }
      const used = await db.execute({
        sql: `SELECT COUNT(*) AS c FROM wardrobe_items WHERE category = ? AND status = 'active'`,
        args: [id],
      });
      if (Number((used.rows[0] as { c?: number }).c) > 0) {
        return fail(res, 400, '这个分类下还有单品，先移走再删');
      }
      await db.execute({ sql: `DELETE FROM categories WHERE id = ?`, args: [id] });
      return ok(res, { id, deleted: true });
    }

    return fail(res, 405, `不支持的请求方法: ${req.method}`);
  } catch (e) {
    return fail(res, 500, '分类操作失败', e instanceof Error ? e.message : String(e));
  }
}
