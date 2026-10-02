/**
 * /api/history —— 穿搭历史（"本月搭配"统计 + 排重数据源 + 穿搭日记）
 *
 * GET    ?userId=xxx[&limit=30][&month=YYYY-MM]   拉取历史（倒序，含详情全字段）
 * POST   body: { userId, itemIds:[...], wornDate?, occasion, weatherSnapshot?,
 *                reason?, makeup?, outfitName?, rating? }
 *        → 事务：写入历史（含推荐文案存档）+ 批量更新单品 wear_count / last_worn_at
 * PATCH  body: { id, userId, notes?, rating?, outfitName? }
 *        → 编辑穿搭日记 / 星级 / 搭配名（详情页「写日记」用）
 *
 * 设计要点：详情页要能复原"那天穿了什么、天气如何、为什么这么搭"，
 * 所以 reason / makeup / weather_snapshot / notes 与单品图片（join 衣橱）一并返回。
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getDb, uuid, todayCn, ensureSchema } from '../lib/db';
import { cors, ok, fail } from '../lib/http';

interface HistoryItemBrief {
  id: string;
  name: string;
  imageUrl: string;
  colorName: string;
}

export async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);
  const db = getDb();
  // notes 等新列惰性迁移（幂等；没这一步老库上 PATCH 会报 no such column）
  if (db) await ensureSchema();

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
          itemNames: ['云朵白衬衫', '斜扣浅蓝牛仔裤', '米色尖头凉鞋'],
          items: [
            { id: 'w_demo_top_01', name: '云朵白衬衫', imageUrl: '', colorName: '白色' },
            { id: 'w_demo_bottom_01', name: '斜扣浅蓝牛仔裤', imageUrl: '', colorName: '浅蓝' },
            { id: 'w_demo_shoe_01', name: '米色尖头凉鞋', imageUrl: '', colorName: '米色' },
          ],
          reason: '波点 + 斜扣牛仔 + 米色尖头凉鞋，避开昨天穿过的款式，温柔又有通勤精致度。',
          notes: '',
          outfitName: '',
          makeup: '蜜桃色腮红 + 奶茶色唇釉，眉毛保持野生感',
          weather: { tempC: 24, feelsLike: 25, condition: '多云', city: '' },
          rating: 5,
          source: 'recommended',
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

      // 解析每条历史的单品 id → 名称 + 图片（详情页要展示大图）
      const rows = r.rows as Array<Record<string, unknown>>;
      const allIds = [...new Set(rows.flatMap((row) => parseIds(row.item_ids)))];
      const briefMap = new Map<string, HistoryItemBrief>();
      if (allIds.length) {
        const ph = allIds.map(() => '?').join(',');
        const itemsRes = await db.execute({
          sql: `SELECT id, name, image_url, color_name FROM wardrobe_items WHERE id IN (${ph})`,
          args: allIds,
        });
        for (const it of itemsRes.rows as Array<Record<string, unknown>>) {
          briefMap.set(String(it.id), {
            id: String(it.id),
            name: String(it.name),
            imageUrl: String(it.image_url ?? ''),
            colorName: String(it.color_name ?? ''),
          });
        }
      }

      const items = rows.map((row) => {
        const ids = parseIds(row.item_ids);
        return {
          id: row.id,
          worn_date: row.worn_date,
          occasion: row.occasion,
          rating: Number(row.rating ?? 5),
          source: row.source ?? 'recommended',
          itemIds: ids,
          itemNames: ids.map((id) => briefMap.get(id)?.name ?? '单品'),
          items: ids.map((id) => briefMap.get(id) ?? { id, name: '单品', imageUrl: '', colorName: '' }),
          reason: str(row.reason),
          notes: str(row.notes),
          outfitName: str(row.outfit_name),
          makeup: str(row.makeup_recommendation),
          weather: parseJson(row.weather_snapshot),
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
      // 事务：写历史（含推荐文案存档，详情页要展示）+ 更新每件单品的穿着统计（排重依据）
      const stmts = [
        {
          sql: `INSERT INTO outfit_history
                (id, user_id, worn_date, item_ids, occasion, weather_snapshot,
                 rating, feedback, source, reason, makeup_recommendation, outfit_name, notes)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`,
          args: [
            uuid(), b.userId, wornDate, JSON.stringify(b.itemIds), b.occasion,
            b.weatherSnapshot ? JSON.stringify(b.weatherSnapshot) : null,
            b.rating ?? null, b.feedback ?? null, b.source === 'manual' ? 'manual' : 'recommended',
            b.reason ? String(b.reason).slice(0, 500) : null,
            b.makeup ? String(b.makeup).slice(0, 300) : null,
            b.outfitName ? String(b.outfitName).slice(0, 60) : null,
            b.notes ? String(b.notes).slice(0, 5000) : null,
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

  // ---------- PATCH：编辑日记 / 星级 / 搭配名 ----------
  if (req.method === 'PATCH') {
    const b = req.body ?? {};
    if (!b.id || !b.userId) return fail(res, 400, 'id 与 userId 必填');
    if (!db) return ok(res, { mode: 'mock', message: 'mock 模式：未落库' });

    const sets: string[] = [];
    const args: Array<string | number> = [];
    if (b.notes !== undefined) {
      sets.push('notes = ?');
      args.push(String(b.notes ?? '').slice(0, 5000));
    }
    if (b.rating !== undefined) {
      const n = Number(b.rating);
      if (Number.isFinite(n)) {
        sets.push('rating = ?');
        args.push(Math.min(5, Math.max(1, Math.round(n))));
      }
    }
    if (b.outfitName !== undefined) {
      sets.push('outfit_name = ?');
      args.push(String(b.outfitName ?? '').slice(0, 60));
    }
    if (!sets.length) return fail(res, 400, '没有要更新的字段');

    try {
      args.push(String(b.id), String(b.userId));
      await db.execute({
        sql: `UPDATE outfit_history SET ${sets.join(', ')} WHERE id=? AND user_id=?`,
        args,
      });
      return ok(res, { id: b.id, updated: sets.length });
    } catch (e) {
      return fail(res, 500, '保存日记失败', e instanceof Error ? e.message : String(e));
    }
  }

  return fail(res, 405, `不支持的请求方法: ${req.method}`);
}

function parseIds(v: unknown): string[] {
  try {
    const arr = JSON.parse(String(v ?? '[]')) as unknown[];
    return Array.isArray(arr) ? arr.map(String) : [];
  } catch {
    return [];
  }
}

function parseJson(v: unknown): Record<string, unknown> | null {
  try {
    const o = JSON.parse(String(v ?? 'null')) as unknown;
    return o && typeof o === 'object' ? (o as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function str(v: unknown): string {
  return v === null || v === undefined ? '' : String(v);
}
