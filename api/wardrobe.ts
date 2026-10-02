/**
 * /api/wardrobe —— 虚拟衣橱单品 CRUD
 *
 * GET    ?userId=xxx&category=tops   拉取列表（可按分类过滤，软删自动排除）
 * POST   body: { userId, name, imageUrl, category, colorName?, colorHex?,
 *                warmthLevel?, formality?, pattern?, subCategory?, brand? }
 * PATCH  body: { id, name?, category?, colorName?, brand? }   编辑基础字段
 * DELETE ?id=xxx                     软删（status → archived，历史记录不因此断链）
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getDb, uuid, ensureSchema } from './lib/db';
import { cors, ok, fail } from './lib/http';
import type { WardrobeItem } from './lib/types';

const MOCK_ITEMS: WardrobeItem[] = [
  { id: 'w_demo_top_01', user_id: 'u_demo', name: '白色波点衬衫', image_url: 'https://placehold.co/400x533?text=Top',
    category: 'tops', color_name: '白色', pattern: 'polka-dot', warmth_level: 2, formality: 3,
    wear_count: 12, last_worn_at: null, status: 'active' },
  { id: 'w_demo_bottom_01', user_id: 'u_demo', name: '斜扣浅蓝牛仔裤', image_url: 'https://placehold.co/400x533?text=Bottoms',
    category: 'bottoms', color_name: '浅蓝', pattern: 'plain', warmth_level: 2, formality: 2,
    wear_count: 8, last_worn_at: null, status: 'active' },
  { id: 'w_demo_shoe_01', user_id: 'u_demo', name: '米色尖头凉鞋', image_url: 'https://placehold.co/400x533?text=Shoes',
    category: 'shoes', color_name: '米色', pattern: 'plain', warmth_level: 1, formality: 3,
    wear_count: 5, last_worn_at: null, status: 'active' },
];

export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);
  const db = getDb();

  // ---------- GET ----------
  if (req.method === 'GET') {
    const userId = String(req.query.userId ?? '');
    const category = req.query.category ? String(req.query.category) : null;
    if (!userId) return fail(res, 400, '缺少 userId');

    if (!db) return ok(res, { mode: 'mock', items: MOCK_ITEMS });

    try {
      await ensureSchema(); // price/image_urls/pinned 列惰性迁移（已存在则忽略）
      const r = await db.execute({
        sql: `SELECT * FROM wardrobe_items
              WHERE user_id = ? AND status = 'active'
              ${category ? 'AND category = ?' : ''}
              ORDER BY pinned DESC, created_at DESC LIMIT 200`,
        args: category ? [userId, category] : [userId],
      });
      return ok(res, { mode: 'turso', items: r.rows });
    } catch (e) {
      return fail(res, 500, '查询衣橱失败', e instanceof Error ? e.message : String(e));
    }
  }

  // ---------- POST ----------
  if (req.method === 'POST') {
    const b = req.body ?? {};
    if (!b.userId || !b.name || !b.imageUrl || !b.category)
      return fail(res, 400, 'userId / name / imageUrl / category 均为必填');

    if (!db) return ok(res, { mode: 'mock', id: 'mock_' + Date.now(), message: 'mock 模式：未落库' });

    try {
      await ensureSchema();
      const id = uuid();
      await db.execute({
        sql: `INSERT INTO wardrobe_items
              (id, user_id, name, image_url, thumbnail_url, image_urls, pinned, category, sub_category,
               color_name, color_hex, color_family, pattern, warmth_level, formality, brand, price, source)
              VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
        args: [
          id, b.userId, b.name, b.imageUrl, b.thumbnailUrl ?? null,
          Array.isArray(b.imageUrls) && b.imageUrls.length
            ? JSON.stringify(b.imageUrls) : null,
          b.pinned ? 1 : 0,
          b.category,
          b.subCategory ?? null, b.colorName ?? null, b.colorHex ?? null,
          b.colorFamily ?? null, b.pattern ?? null,
          Number(b.warmthLevel ?? 2), Number(b.formality ?? 2),
          b.brand ?? null, b.price != null && b.price !== '' ? Number(b.price) : null,
          b.source ?? 'upload',
        ],
      });
      return ok(res, { id });
    } catch (e) {
      return fail(res, 500, '写入衣橱失败', e instanceof Error ? e.message : String(e));
    }
  }

  // ---------- PATCH（编辑基础字段） ----------
  if (req.method === 'PATCH') {
    const b = req.body ?? {};
    if (!b.id) return fail(res, 400, '缺少 id');
    if (!db) return ok(res, { mode: 'mock', message: 'mock 模式：未落库' });

    // 只更新传入的字段（name/category/colorName/brand/price/imageUrl/imageUrls/pinned）
    const sets: string[] = [];
    const args: (string | number | null)[] = [];
    if (b.name) { sets.push('name = ?'); args.push(String(b.name)); }
    if (b.category) { sets.push('category = ?'); args.push(String(b.category)); }
    if (b.colorName !== undefined) { sets.push('color_name = ?'); args.push(b.colorName ? String(b.colorName) : null); }
    if (b.brand !== undefined) { sets.push('brand = ?'); args.push(b.brand ? String(b.brand) : null); }
    if (b.price !== undefined) { sets.push('price = ?'); args.push(b.price === null || b.price === '' ? null : Number(b.price)); }
    if (b.imageUrl !== undefined) {
      // 允许空串清空主图（列 NOT NULL，空串即"无主图"，客户端回退 emoji 占位）
      sets.push('image_url = ?'); args.push(b.imageUrl ? String(b.imageUrl) : '');
    }
    if (b.imageUrls !== undefined) {
      sets.push('image_urls = ?');
      args.push(Array.isArray(b.imageUrls) && b.imageUrls.length
        ? JSON.stringify(b.imageUrls) : null);
    }
    if (b.pinned !== undefined) { sets.push('pinned = ?'); args.push(b.pinned ? 1 : 0); }
    if (!sets.length) return fail(res, 400, '没有需要更新的字段');

    try {
      await db.execute({
        sql: `UPDATE wardrobe_items SET ${sets.join(', ')}, updated_at = datetime('now') WHERE id = ?`,
        args: [...args, String(b.id)],
      });
      return ok(res, { id: b.id, updated: sets.length });
    } catch (e) {
      return fail(res, 500, '更新单品失败', e instanceof Error ? e.message : String(e));
    }
  }

  // ---------- DELETE（软删） ----------
  if (req.method === 'DELETE') {
    const id = String(req.query.id ?? '');
    if (!id) return fail(res, 400, '缺少 id');
    if (!db) return ok(res, { mode: 'mock', message: 'mock 模式：未落库' });

    try {
      await db.execute({
        sql: `UPDATE wardrobe_items SET status='archived', updated_at=datetime('now') WHERE id = ?`,
        args: [id],
      });
      return ok(res, { id, archived: true });
    } catch (e) {
      return fail(res, 500, '删除失败', e instanceof Error ? e.message : String(e));
    }
  }

  return fail(res, 405, `不支持的请求方法: ${req.method}`);
}
