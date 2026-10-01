/**
 * 初始化远程 Turso：执行 db/schema.sql + db/seed.sql
 * 幂等设计（CREATE TABLE IF NOT EXISTS + ON CONFLICT DO NOTHING），可安全重复执行。
 *
 * 运行（二选一）：
 *   TURSO_URL=... TURSO_AUTH_TOKEN=... node scripts/init-remote.mjs
 *   或项目根配好 .env 后直接：node scripts/init-remote.mjs
 */
import { createClient } from '@libsql/client';
import { existsSync, readFileSync } from 'node:fs';

// 简易加载 .env（不覆盖已有环境变量）
if (existsSync('.env')) {
  for (const line of readFileSync('.env', 'utf8').split('\n')) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].trim();
  }
}

const url = process.env.TURSO_URL;
const token = process.env.TURSO_AUTH_TOKEN;
if (!url || !token) {
  console.error('❌ 缺少 TURSO_URL / TURSO_AUTH_TOKEN（检查 .env 或命令行环境变量）');
  process.exit(1);
}

const db = createClient({ url, authToken: token });
const splitSql = (s) => s.split(';').map((x) => x.trim()).filter(Boolean);

for (const stmt of splitSql(readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8'))) {
  await db.execute(stmt);
}
for (const stmt of splitSql(readFileSync(new URL('../db/seed.sql', import.meta.url), 'utf8'))) {
  await db.execute(stmt);
}

const tables = await db.execute(
  "SELECT name FROM sqlite_master WHERE type='table'",
);
console.log(`✅ 远程 Turso 初始化完成 → ${url}`);
console.log('   表:', tables.rows.map((r) => r.name).join(', '));
