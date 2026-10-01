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
import { createClient, type Client } from '@libsql/client';

let cached: Client | null = null;

export function getDb(): Client | null {
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
