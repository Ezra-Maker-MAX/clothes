/**
 * /api/history —— 穿搭历史（"本月搭配"统计 + 排重数据源）
 *
 * GET  ?userId=xxx[&limit=30][&month=YYYY-MM]   拉取历史（倒序）
 * POST body: { userId, itemIds:[...], wornDate?, occasion,
 *              weatherSnapshot?, rating?, feedback? }
 *      → 事务：写入历史 + 批量更新单品 wear_count / last_worn_at
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getDb, uuid, todayCn } from '../_lib/db';
import { cors, ok, fail } from '../_lib/http';

export async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);
  const db = getDb();

  // ---------- GET ----------
  if (req.method === 'GET') {
    const userId = String(req.query.userId ?? '');
    const limit = Math.min(Number(req.query.limit ?? 30), 100);
    const month = req.query.month ? String(req.query.month) : null;
    if (!userId) return fail(res, 400, '缺少 userId');

    if (!db) {
      return ok(res, {
        mode: 'mock',
        monthStats: { thisMonth: 18, wardrobeItems: 47, neverWorn: 9 },
        items: [{
          id: 'h_demo', worn_date: todayCn(), occasion: 'commute',
          item_ids: ['w_demo_top_01', 'w_demo_bottom_01', 'w_demo_shoe_01'],
          reason: '经典通勤组合', rating: 5,
        }],
      });
    }

    try {
      const r = await db.execute({
        sql: `SELECT * FROM outfit_history
              WHERE user_id = ? ${month ? "AND strftime('%Y-%m', worn_date) = ?" : ''}
              ORDER BY worn_date DESC LIMIT ?`,
        args: month ? [userId, month, limit] : [userId, limit],
      });
      // 顺手给首页统计卡片：本月搭配数
      const stat = await db.execute({
        sql: `SELECT COUNT(*) AS c FROM outfit_history
              WHERE user_id=? AND strftime('%Y-%m', worn_date)=strftime('%Y-%m','now')`,
        args: [userId],
      });
      // 解析每条历史的单品 id → 名称，便于前端直接渲染搭配摘要
      const rows = r.rows as Array<Record<string, unknown>>;
      const allIds = [...new Set(rows.flatMap((r) => {
        try { return JSON.parse(String(r.item_ids ?? '[]')) as string[]; } catch { return []; }
      }))];
      const nameMap: Record<string, string> = {};
      if (allIds.length) {
        const ph = allIds.map(() => '?').join(',');
        const itemsRes = await db.execute({
          sql: `SELECT id, name FROM wardrobe_items WHERE id IN (${ph})`,
          args: allIds,
        });
        for (const it of itemsRes.rows as Array<Record<string, unknown>>) {
          nameMap[String(it.id)] = String(it.name);
        }
      }
      const items = rows.map((r) => {
        const ids = (() => {
          try { return JSON.parse(String(r.item_ids ?? '[]')) as string[]; } catch { return []; }
        })();
        return {
          id: r.id,
          worn_date: r.worn_date,
          occasion: r.occasion,
          rating: r.rating ?? 5,
          source: r.source ?? 'recommended',
          itemIds: ids,
          itemNames: ids.map((id) => nameMap[id] ?? '单品'),
        };
      });
      return ok(res, { mode: 'turso', items, monthStats: { thisMonth: Number(stat.rows[0]?.c ?? 0) } });
    } catch (e) {
      return fail(res, 500, '查询历史失败', e instanceof Error ? e.message : String(e));
    }
  }

  // ---------- POST：记录"就穿这套" ----------
  if (req.method === 'POST') {
    const b = req.body ?? {};
    if (!b.userId || !Array.isArray(b.itemIds) || !b.itemIds.length || !b.occasion)
      return fail(res, 400, 'userId / itemIds / occasion 均为必填');

    const wornDate = b.wornDate ?? todayCn();

    if (!db) return ok(res, { mode: 'mock', message: 'mock 模式：未落库' });

    try {
      // 事务：写历史 + 更新每件单品的穿着统计（排重依据）
      const stmts = [
        {
          sql: `INSERT INTO outfit_history
                (id, user_id, worn_date, item_ids, occasion, weather_snapshot, rating, feedback, source)
                VALUES (?,?,?,?,?,?,?,?,?)`,
          args: [
            uuid(), b.userId, wornDate, JSON.stringify(b.itemIds), b.occasion,
            b.weatherSnapshot ? JSON.stringify(b.weatherSnapshot) : null,
            b.rating ?? null, b.feedback ?? null, b.source === 'manual' ? 'manual' : 'recommended',
          ],
        },
        ...b.itemIds.map((id: string) => ({
          sql: `UPDATE wardrobe_items
                SET wear_count = wear_count + 1, last_worn_at = ?, updated_at = datetime('now')
                WHERE id = ?`,
          args: [wornDate, id],
        })),
      ];
      await db.batch(stmts, 'write');
      return ok(res, { wornDate, recorded: b.itemIds.length });
    } catch (e) {
      return fail(res, 500, '记录历史失败', e instanceof Error ? e.message : String(e));
    }
  }

  return fail(res, 405, `不支持的请求方法: ${req.method}`);
}
