#!/usr/bin/env node
/**
 * 清理 api/ 目录的历史残留文件（Vercel 12 函数上限问题的地面清理）。
 *
 * 背景：zip 解压「只覆盖同名文件、不删除旧文件」，历史版本曾把
 * recommend.ts / wardrobe.ts / lib/ / _handlers/ / _lib/ 等放在 api/ 下，
 * 反复解包后这些文件一直留在本地，git add -A 又提交回仓库，
 * 导致 Vercel 数出 >12 个 Serverless Functions 部署失败。
 *
 * vercel.json 已改用显式 builds（残留文件不会再被部署），
 * 本脚本用于把仓库本身也清理干净。可重复执行（幂等）。
 *
 * 用法：在项目根目录执行  node scripts/clean-api.mjs
 * 之后：git add -A && git commit -m "clean api dir" && git push
 */
import fs from 'node:fs';
import path from 'node:path';

const KEEP = new Set(['gateway.ts']); // api/ 里唯一合法的文件
const apiDir = path.resolve(process.cwd(), 'api');

if (!fs.existsSync(apiDir)) {
  console.log('[clean-api] 未找到 api/ 目录，无需清理。');
  process.exit(0);
}

let removed = 0;
for (const name of fs.readdirSync(apiDir)) {
  if (KEEP.has(name)) continue;
  const p = path.join(apiDir, name);
  fs.rmSync(p, { recursive: true, force: true });
  removed++;
  console.log(`[clean-api] 已删除 api/${name}`);
}

const left = fs.readdirSync(apiDir);
console.log(`[clean-api] 完成：删除 ${removed} 项，api/ 现存内容 → [${left.join(', ')}]`);
if (left.join(',') !== 'gateway.ts') {
  console.log('[clean-api] ⚠️ api/ 下出现意外文件，请人工确认！');
} else {
  console.log('[clean-api] ✅ api/ 只剩 gateway.ts，符合预期。');
  console.log('[clean-api] 下一步：git add -A && git commit -m "clean api dir" && git push');
}
