/**
 * GET /api/health —— 跑通验证接口（浏览器直接打开即可测）
 *
 * ✅ 已配置 TURSO_URL / TURSO_AUTH_TOKEN：
 *    返回真实连接状态 + 四张表实时行数
 * ⚠️ 未配置：
 *    返回 mock 模式 + 配置指引（保证先跑通，不白屏）
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getDb } from '../lib/db';
import { cors, ok } from '../lib/http';

const TABLES = ['users', 'wardrobe_items', 'outfit_history', 'daily_recommendations'];

export async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);

  // getDb() 若同步抛错（最常见：环境变量复制不完整，首尾混入空格/换行），
  // 必须接住并把真实错误透出，否则线上表现为难排查的 500 FUNCTION_INVOCATION_FAILED
  let db: ReturnType<typeof getDb>;
  try {
    db = getDb();
  } catch (e) {
    return ok(res, {
      mode: 'db_init_error',
      hint: '数据库客户端初始化失败：请检查 Vercel 环境变量 TURSO_URL / TURSO_AUTH_TOKEN '
          + '是否完整粘贴（首尾不能有空格或换行），修改环境变量后需 Redeploy 才生效。',
      error: e instanceof Error ? e.message : String(e),
    });
  }

  // ---- mock 模式：环境变量未配置 ----
  if (!db) {
    return ok(res, {
      mode: 'mock',
      hint: '检测到未配置 TURSO_URL / TURSO_AUTH_TOKEN，当前返回演示数据。'
          + '请执行 turso db create 拿到 URL，再在 Vercel 或本地 .env 中配置。',
      env_needed: ['TURSO_URL', 'TURSO_AUTH_TOKEN'],
      sample: {
        app: '衣念',
        tables: { users: 1, wardrobe_items: 3, outfit_history: 1, daily_recommendations: 0 },
        demo_recommendation: {
          occasion: '日常通勤',
          items: ['白色波点衬衫', '斜扣浅蓝牛仔裤', '米色尖头凉鞋'],
          reason: '波点 + 斜扣牛仔 + 米色尖头凉鞋，避开昨天穿过的款式，温柔又有通勤精致度。',
        },
      },
      time: new Date().toISOString(),
    });
  }

  // ---- 真实模式：ping 数据库 + 统计行数 ----
  try {
    await db.execute('SELECT 1');
    const counts: Record<string, number> = {};
    for (const t of TABLES) {
      const r = await db.execute(`SELECT COUNT(*) AS c FROM ${t}`);
      counts[t] = Number(r.rows[0]?.c ?? 0);
    }
    return ok(res, {
      mode: 'turso',
      db: String(process.env.TURSO_URL).replace(/libsql:\/\/(.+?)\..*/, 'libsql://$1…'),
      tables: counts,
      time: new Date().toISOString(),
    });
  } catch (e) {
    return ok(res, {
      mode: 'turso_uninitialized',
      hint: '连接成功但查询失败，请先执行 db/schema.sql 建表：'
          + 'turso db shell <库名> < db/schema.sql',
      error: e instanceof Error ? e.message : String(e),
    });
  }
}
