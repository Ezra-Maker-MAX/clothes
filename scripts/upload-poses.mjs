#!/usr/bin/env node
/**
 * 姿势参考图批量导入 Vercel Blob（私密 store）
 *
 * 用法：
 *   PRIVATE_BLOB_READ_WRITE_TOKEN=<token> node scripts/upload-poses.mjs            # 全量导入
 *   PRIVATE_BLOB_READ_WRITE_TOKEN=<token> node scripts/upload-poses.mjs --dry-run   # 只看会传哪些
 *   PRIVATE_BLOB_READ_WRITE_TOKEN=<token> node scripts/upload-poses.mjs --limit 20 # 先试 20 张
 *
 * Token 从Vercel → Storage → 你的私密 Blob Store → Tokens → Create Token 获取
 * （勾 Private Access）。用 token 而不是 OIDC 的原因：脚本跑在 Vercel 之外，
 * 拿不到 OIDC 凭证。
 *
 *幂等：按 pathname 去重，已存在的跳过（可用 --force 重传覆盖）。
 * 并发 4：再高容易被 Vercel 限流（429），反而更慢。
 */
import { readFile, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const IMG_DIR = join(ROOT, 'assets', 'poses', 'img');
const INDEX = join(ROOT, 'assets', 'poses', 'index.json');

const args = process.argv.slice(2);
const DRY = args.includes('--dry-run');
const FORCE = args.includes('--force');
const limitArg = args.indexOf('--limit');
const LIMIT = limitArg >= 0 ? Number(args[limitArg + 1]) : Infinity;

const token = (process.env.PRIVATE_BLOB_READ_WRITE_TOKEN ?? '').trim();
const storeId = (process.env.PRIVATE_BLOB_STORE_ID ?? '').trim();
if (!token && !storeId) {
  console.error(
    '缺少凭据：设置 PRIVATE_BLOB_READ_WRITE_TOKEN（Vercel → Storage → 私密 Store → Tokens → Create Token，勾 Private Access）',
  );
  process.exit(1);
}
if (!existsSync(IMG_DIR)) {
  console.error(`找不到图片目录：${IMG_DIR}`);
  process.exit(1);
}

const auth = { ...(storeId ? { storeId } : {}), ...(token ? { token } : {}), access: 'private' };

async function listExisting() {
  const { list } = await import('@vercel/blob');
  const seen = new Set();
  let cursor;
  do {
    const r = await list({ ...auth, limit: 1000, cursor });
    for (const b of r.blobs ?? []) seen.add(b.pathname);
    cursor = r.cursor;
  } while (cursor);
  return seen;
}

const index = JSON.parse(await readFile(INDEX, 'utf8'));
const files = (await readdir(IMG_DIR)).filter((f) => f.endsWith('.webp'));
const items = index.items
  .map((it) => ({ ...it, file: join(IMG_DIR, basename(it.image)) }))
  .filter((it) => files.includes(basename(it.file)));

// 同一个 imagePath 可能出现在多个分组行里（27 个跨组姿势），上传只需一次
const uniq = new Map();
for (const it of items) if (!uniq.has(it.image)) uniq.set(it.image, it);
const targets = [...uniq.values()].slice(0, Number.isFinite(LIMIT) ? LIMIT : undefined);

console.log(`清单 ${items.length} 行 → 去重后 ${uniq.size} 张图，本次处理 ${targets.length} 张`);
console.log(`凭据模式：${storeId ? 'PRIVATE_BLOB_STORE_ID(OIDC)' : 'PRIVATE_BLOB_READ_WRITE_TOKEN'}`);

if (DRY) {
  for (const t of targets.slice(0, 10)) {
    const st = await readFile(t.file).then((b) => (b.length / 1024).toFixed(1) + 'KB');
    console.log(`  [dry] → ${t.image}  ${st}`);
  }
  console.log('dry-run 结束，未做任何写入');
  process.exit(0);
}

const existing = FORCE ? new Set() : await listExisting();
if (!FORCE) console.log(`已存在 ${existing.size} 个对象，将跳过`);

const CONCURRENCY = 4;
let ok = 0;
let skipped = 0;
let failed = 0;

async function uploadOne(t) {
  if (existing.has(t.image)) {
    skipped++;
    return;
  }
  const buf = await readFile(t.file);
  const { put } = await import('@vercel/blob');
  try {
    await put(t.image, buf, {
      ...auth,
      contentType: 'image/webp',
      addRandomSuffix: false,
      // 不可变内容：同名覆盖即可，不必依赖随机后缀
      allowOverwrite: true,
    });
    ok++;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    // 单张失败不中断整批：205 张里个别失败不该让整个任务白跑
    if (/store has been suspended|exceeded|429/i.test(msg)) throw new Error(msg);
    failed++;
    console.warn(`  ✗ ${t.image}: ${msg.slice(0, 120)}`);
  }
}

const queue = [...targets];
const workers = Array.from({ length: CONCURRENCY }, async () => {
  for (;;) {
    const t = queue.shift();
    if (!t) return;
    try {
      await uploadOne(t);
    } catch (e) {
      // 致命错误（store 被封停/ 配额超限）→ 立刻停下，别继续烧请求
      console.error('\n致命错误，已中止：', e instanceof Error ? e.message : e);
      console.error('若提示用量超限，只能提 Vercel Support 工单，代码侧无解。');
      process.exit(1);
    }
    if ((ok + skipped + failed) % 20 === 0) {
      console.log(`  进度 ${ok + skipped + failed}/${targets.length}（成功 ${ok} 跳过 ${skipped} 失败 ${failed}）`);
    }
  }
});
await Promise.all(workers);

console.log(`\n完成：成功 ${ok}，跳过 ${skipped}，失败 ${failed}`);
if (failed > 0) process.exit(1);
console.log('现在 GET /api/pose-image?pathname=poses/0000038_00004.webp 应该能取到图。');