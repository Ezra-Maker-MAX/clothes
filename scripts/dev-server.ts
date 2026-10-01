/**
 * 本地联调 Server —— 把 api 下的 *.ts 的 Vercel handler 挂载成真实 HTTP 接口
 *
 * 用途：沙箱/本机无法部署 Vercel 时，用它在本地跑通「换一套 / 就穿这套」真实数据流。
 *   - 通过 LOCAL_DB 连本地 SQLite 文件模拟 Turso（见 api/lib/db.ts）
 *   - 通过 WEATHER_API_KEY 接入和风天气（缺失则降级 mock）
 * 部署到 Vercel 后无需此文件，Vercel 会按 api 下的 *.ts 自动识别为函数。
 *
 * 运行：LOCAL_DB=./local.db npm run local   （默认端口 3001）
 */
import express from 'express';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

// 本地调试：自动加载 .env（不覆盖已存在的环境变量；Vercel 线上由平台注入，跳过）
const envFile = path.resolve(process.cwd(), '.env');
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, 'utf8').split('\n')) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].trim();
  }
}

async function main() {
  const app = express();
  app.use(express.json());
  // 若 Flutter Web 构建产物存在，则同时托管（本地联调时单端口即可预览真实数据流）
  const webDir = path.resolve(process.cwd(), 'app/build/web');
  app.use(express.static(webDir));

  const apiDir = path.resolve(process.cwd(), 'api');
  const port = Number(process.env.PORT ?? 3001);

  for (const file of readdirSync(apiDir)) {
    if (!file.endsWith('.ts')) continue;
    const name = file.replace(/\.ts$/, '');
    const mod = await import(pathToFileURL(path.join(apiDir, file)).href);
    if (typeof mod.default !== 'function') continue;
    // 与 Vercel 路由一致：/api/<name>
    app.all(`/api/${name}`, (req, res) => mod.default(req, res));
  }

  app.listen(port, () => {
    const mode = process.env.TURSO_URL
      ? 'Turso 远程'
      : process.env.LOCAL_DB
        ? `本地 SQLite (${process.env.LOCAL_DB})`
        : 'mock（未配置 DB 凭证）';
    console.log(`[dev] 本地联调 API 已启动 → http://localhost:${port}`);
    console.log(`[dev] DB 模式: ${mode} ｜ 天气: ${process.env.WEATHER_API_KEY ? '和风天气' : 'mock 降级'}`);
  });
}

main().catch((e) => {
  console.error('[dev] 启动失败:', e);
  process.exit(1);
});
