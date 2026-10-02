/**
 * /api/recommend —— 每日推荐（缓存优先，省钱核心）
 *
 * GET ?userId=xxx&occasion=commute[&date=YYYY-MM-DD][&refresh=1][&tempC=24][&location=101020100]
 *
 * 逻辑链：
 *  1) 查 daily_recommendations 缓存（UNIQUE: user+date+occasion）→ 命中直接返回
 *  2) refresh=1（前端"换一套"）→ 覆盖缓存重新生成，swap_count+1
 *  3) 生成：读衣橱 → 情景引擎（排重+厚度+正式度）→ 写缓存
 *  4) 天气：和风天气 API + IP 自动定位城市（未配 WEATHER_API_KEY 时温度降级 mock 24°C，
 *     但城市名仍按访问 IP 定位，不会再永远显示"上海"）
 *
 * 环境变量：WEATHER_API_KEY（必需，取真实温度）/ WEATHER_LOCATION（可选，固定城市，优先级高于 IP 定位）
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getDb, uuid, todayCn } from '../lib/db';
import { cors, ok, fail, clientIp } from '../lib/http';
import { pickOutfit, buildReason, MAKEUP } from '../lib/engine';
import type { WardrobeItem, Occasion, WeatherSnapshot } from '../lib/types';
import { getWeather } from '../lib/weather';
import { polishReason } from '../lib/llm';

/** 场合 → 展示标签（LLM 润色与前端共用口径） */
const OCCASION_LABEL: Record<Occasion, string> = {
  commute: '日常通勤', date: '约会', interview: '面试', casual: '休闲日常', party: '聚会',
};

const MOCK_RECOMMEND = {
  occasion: 'commute',
  date: todayCn(),
  weather: { tempC: 24, feelsLike: 25, condition: '多云' },
  items: {
    top: { id: 'w_demo_top_02', name: '燕麦色针织开衫', image_url: 'https://placehold.co/400x533?text=Top', color_name: '燕麦色', pattern: 'plain' },
    bottom: { id: 'w_demo_bottom_02', name: '白色阔腿西装裤', image_url: 'https://placehold.co/400x533?text=Bottoms', color_name: '白色', pattern: 'plain' },
    shoe: { id: 'w_demo_shoe_02', name: '裸色平底穆勒鞋', image_url: 'https://placehold.co/400x533?text=Shoes', color_name: '裸色', pattern: 'plain' },
  },
  makeup: MAKEUP.commute,
  reason: '静奢通勤风 · 燕麦针织的软糯刚好压住秋风，白色阔腿裤把利落感拉满，避开了昨天穿过的款式。',
  fromCache: false,
};

export async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);
  const db = getDb();

  const userId = String(req.query.userId ?? '');
  if (!userId) return fail(res, 400, '缺少 userId');
  const occasion = (String(req.query.occasion ?? 'commute')) as Occasion;
  const date = String(req.query.date ?? todayCn());
  const refresh = req.query.refresh === '1';
  const location = req.query.location ? String(req.query.location) : undefined;
  const overrideTemp = req.query.tempC ? Number(req.query.tempC) : null;

  // 实时天气：和风 API（缺 KEY/异常降级 mock）+ IP 自动定位城市；
  // query 传 tempC 仍可覆盖（仅调试演示用，App 端默认不传，避免锁死 24°C）
  const wx = await getWeather({ location, ip: clientIp(req) });
  const tempC = overrideTemp ?? wx.tempC;
  const weather: WeatherSnapshot = {
    tempC, feelsLike: wx.feelsLike, condition: wx.condition, city: wx.city,
  };

  if (!db) {
    return ok(res, {
      mode: 'mock', weatherSource: wx.source, weatherLocatedBy: wx.locatedBy,
      ...MOCK_RECOMMEND, weather,
    });
  }

  try {
    // ---------- 1) 读缓存 ----------
    if (!refresh) {
      const hit = await db.execute({
        sql: `SELECT * FROM daily_recommendations
              WHERE user_id=? AND recommend_date=? AND occasion=?`,
        args: [userId, date, occasion],
      });
      if (hit.rows.length) {
        const row = hit.rows[0];
        await db.execute({
          sql: `UPDATE daily_recommendations SET status='shown', updated_at=datetime('now') WHERE id=?`,
          args: [String(row.id)],
        });
        return ok(res, {
          mode: 'turso', fromCache: true, id: row.id,
          occasion, date,
          weatherSource: wx.source, weatherLocatedBy: wx.locatedBy,
          // 天气以本次实时结果为准：缓存里的快照可能是几小时前的旧城市
          weather,
          ...JSON.parse(String(row.outfit_json)),       // items + reason + makeup
        });
      }
    }

    // ---------- 2) 生成：读衣橱 + 排重 ----------
    const items = await db.execute({
      sql: `SELECT * FROM wardrobe_items WHERE user_id=? AND status='active'`,
      args: [userId],
    });

    // 分类翻译层：item.category 存的是分类 id（内置行 id=引擎 key），
    // 动态分类经 categories.engine_key 映射回引擎适配类别 —— 引擎只认 key，永不失明
    const catRows = await db.execute({
      sql: `SELECT id, engine_key FROM categories WHERE user_id=?`,
      args: [userId],
    });
    const engineMap: Record<string, string> = {};
    for (const r of catRows.rows as Array<Record<string, unknown>>) {
      engineMap[String(r.id)] = String(r.engine_key);
    }
    const wardrobe = (items.rows as unknown as Array<Record<string, unknown>>).map((r) => ({
      ...r,
      category: engineMap[String(r.category)] ?? String(r.category),
    })) as unknown as WardrobeItem[];

    // 排重：最近 2 天穿过的单品一律避开
    // （显式断言行类型：不依赖 @libsql/core 转发类型链，Vercel 构建更稳）
    const recent = await db.execute({
      sql: `SELECT item_ids FROM outfit_history
            WHERE user_id=? AND worn_date >= date(?, '-2 day')`,
      args: [userId, date],
    });
    const recentRows = recent.rows as Array<Record<string, unknown>>;
    const excludeIds = recentRows.flatMap(r => {
      try { return JSON.parse(String(r.item_ids ?? '[]')) as string[]; } catch { return []; }
    });

    // 「换一套」轮换：基于已换次数在评分前三候选间轮换，确保每次换出不同组合
    let rotation = 0;
    if (refresh) {
      const cur = await db.execute({
        sql: `SELECT swap_count FROM daily_recommendations WHERE user_id=? AND recommend_date=? AND occasion=?`,
        args: [userId, date, occasion],
      });
      rotation = Number((cur.rows[0] as { swap_count?: number } | undefined)?.swap_count ?? 0) + 1;
    }
    const picked = pickOutfit(wardrobe, { occasion, tempC, excludeIds, rotation });
    if (!picked) {
      return fail(res, 404, '衣橱单品不足（至少需要 1 件上衣 + 1 件下装 + 1 双鞋），先去衣橱里补货吧');
    }

    const ruleReason = buildReason(picked.outfit.top, picked.outfit.bottom, picked.outfit.shoe, weather, picked.avoidedCount);
    // LLM 润色（引擎 v0.2）：未配 KEY / 失败 / 超时都自动降级回规则文案
    const polished = await polishReason({
      ruleReason,
      occasionLabel: OCCASION_LABEL[occasion] ?? '日常',
      condition: weather.condition,
      feelsLike: weather.feelsLike,
      avoidedCount: picked.avoidedCount,
    });
    const reason = polished ?? ruleReason;
    const makeup = MAKEUP[occasion] ?? MAKEUP.casual;
    const outfitJson = { items: picked.outfit, reason, makeup };

    // ---------- 3) 写缓存（UPSERT，refresh 时覆盖） ----------
    const recId = uuid();
    await db.execute({
      sql: `INSERT INTO daily_recommendations
            (id, user_id, recommend_date, occasion, weather_snapshot,
             outfit_json, item_ids, reason, makeup, status, swap_count, model, expires_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,'rule-based', datetime(?, '+1 day'))
            ON CONFLICT(user_id, recommend_date, occasion) DO UPDATE SET
              weather_snapshot=excluded.weather_snapshot,
              outfit_json=excluded.outfit_json,
              item_ids=excluded.item_ids,
              reason=excluded.reason,
              makeup=excluded.makeup,
              status='shown',
              swap_count=daily_recommendations.swap_count+1,
              updated_at=datetime('now')`,
      args: [
        recId, userId, date, occasion, JSON.stringify(weather),
        JSON.stringify(outfitJson),
        JSON.stringify(Object.values(picked.outfit).map(i => i.id)),
        reason, makeup, 'shown', refresh ? 0 : 0, date,
      ],
    });

    return ok(res, {
      mode: 'turso', fromCache: false, id: recId,
      occasion, date, weather, ...outfitJson,
      avoidedCount: picked.avoidedCount,
    });
  } catch (e) {
    return fail(res, 500, '生成推荐失败', e instanceof Error ? e.message : String(e));
  }
}
