/**
 * Turso (LibSQL) 客户端封装
 *
 * ⚠️ 环境变量（Vercel Dashboard → Settings → Environment Variables 配置）：
 *   TURSO_URL         libsql://your-db-xxx.turso.io
 *   TURSO_AUTH_TOKEN  turso db tokens create your-db 生成
 *
 * 未配置时返回 null → 各接口自动降级为 mock 模式，
 * 保证"先跑通"阶段网页上也能看到数据结构。
 */
import path from 'node:path';
import { createClient } from '@libsql/client';

// 不直接 import Client 类型：@libsql/client 的类型经 @libsql/core 转发导出，
// 在 Vercel 构建环境的解析模式下该转发链可能断裂（TS2459）。
// 用 ReturnType 推导则任何环境都稳定。
type DbClient = ReturnType<typeof createClient>;

let cached: DbClient | null = null;

export function getDb(): DbClient | null {
  const url = process.env.TURSO_URL;
  const token = process.env.TURSO_AUTH_TOKEN;
  if (url && token) {
    if (!cached) {
      // node runtime 用默认入口即可；若迁到 Edge Runtime 需换 '@libsql/client/web'
      cached = createClient({ url, authToken: token });
    }
    return cached;
  }

  // 本地联调模式：未配置 TURSO 凭证时，用本地 SQLite 文件模拟 Turso
  // （libsql 支持 file: 协议，schema.sql 可直接建表，便于沙箱/本机跑通真实数据流）
  // ⚠️ LOCAL_DB 仅本地调试用，部署 Vercel 时请改用 TURSO_URL + TURSO_AUTH_TOKEN
  const local = process.env.LOCAL_DB;
  if (local) {
    if (!cached) cached = createClient({ url: `file:${path.resolve(local)}` });
    return cached;
  }

  return null;
}

/** 生成 UUID（node 20+ 原生支持） */
export function uuid(): string {
  return crypto.randomUUID();
}

/** 今天日期 YYYY-MM-DD（东八区口径） */
export function todayCn(): string {
  return new Date(Date.now() + 8 * 3600_000).toISOString().slice(0, 10);
}

// ---------------------------------------------------------------------------
// 惰性 schema 迁移：线上 Turso 库已建基础表，这里只做「增量」且全部幂等——
// CREATE TABLE IF NOT EXISTS 重复执行无副作用；ALTER ADD COLUMN 重复会报
// duplicate column，捕获忽略即可。每个 serverless 实例只跑一次（schemaReady）。
// 新增表/列时同步更新 db/schema.sql 保持文档一致。
// ---------------------------------------------------------------------------
let schemaReady = false;

export async function ensureSchema(): Promise<void> {
  const db = getDb();
  if (!db || schemaReady) return;
  try {
    await db.execute(`CREATE TABLE IF NOT EXISTS categories (
      id         TEXT PRIMARY KEY,
      user_id    TEXT NOT NULL,
      name       TEXT NOT NULL,
      engine_key TEXT NOT NULL,              -- 映射到推荐引擎的适配类别（tops/bottoms/...）
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_builtin INTEGER NOT NULL DEFAULT 0, -- 内置分类不可删除
      created_at TEXT DEFAULT (datetime('now'))
    )`);
    try {
      await db.execute(`ALTER TABLE wardrobe_items ADD COLUMN price NUMERIC`);
    } catch {
      // duplicate column name → 已迁移过，忽略
    }
    try {
      await db.execute(`ALTER TABLE wardrobe_items ADD COLUMN image_urls TEXT`);
    } catch {
      // 已迁移过
    }
    try {
      await db.execute(`ALTER TABLE wardrobe_items ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0`);
    } catch {
      // 已迁移过
    }
    schemaReady = true;
  } catch (e) {
    // 迁移失败不阻断请求：调用方各自降级（分类用内置、价格不展示）
    console.warn('[db] ensureSchema 失败（不阻断）：', e instanceof Error ? e.message : e);
  }
}
