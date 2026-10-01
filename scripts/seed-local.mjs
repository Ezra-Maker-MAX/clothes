/**
 * 初始化本地 SQLite（模拟 Turso）并灌入演示数据
 * 运行：node scripts/seed-local.mjs   （可前置 LOCAL_DB=./local.db）
 *
 * 注意：@libsql/client 的 execute() 仅执行单条语句，故按分号拆分逐条执行。
 */
import { createClient } from '@libsql/client';
import { readFileSync, rmSync } from 'node:fs';

const dbPath = process.env.LOCAL_DB ?? './local.db';
// 重建：删旧文件，保证 schema 每次干净落库
try { rmSync(dbPath, { force: true }); } catch { /* 首次无文件 */ }

const db = createClient({ url: `file:${dbPath}` });

const splitSql = (s) => s.split(';').map((x) => x.trim()).filter(Boolean);
for (const stmt of splitSql(readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8'))) {
  await db.execute(stmt);
}
for (const stmt of splitSql(readFileSync(new URL('../db/seed.sql', import.meta.url), 'utf8'))) {
  await db.execute(stmt);
}
console.log(`✅ 本地 SQLite 已建表并灌入演示数据 → ${dbPath}`);
