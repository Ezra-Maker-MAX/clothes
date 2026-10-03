import { test } from 'node:test';
import assert from 'node:assert';

test('未配置时明确报 not configured', async () => {
  delete process.env.PRIVATE_BLOB_STORE_ID;
  delete process.env.PRIVATE_BLOB_READ_WRITE_TOKEN;
  const { privateBlobConfigured, PRIVATE_BLOB_SETUP_HINT } =
    await import('../server/lib/blob.ts');
  assert.equal(privateBlobConfigured(), false);
  assert.ok(PRIVATE_BLOB_SETUP_HINT.includes('Private'));
});

test('配了任一变量即视为已配置', async () => {
  const { privateBlobConfigured } = await import('../server/lib/blob.ts');
  process.env.PRIVATE_BLOB_STORE_ID = 'store_xxx';
  assert.equal(privateBlobConfigured(), true);
  delete process.env.PRIVATE_BLOB_STORE_ID;
});

test('blobHealth 输出里必须带 private 段（否则私密故障查不出来）', async () => {
  process.env.PRIVATE_BLOB_STORE_ID = '';
  delete process.env.PRIVATE_BLOB_STORE_ID;
  const { blobHealth } = await import('../server/lib/blob.ts');
  const h = await blobHealth();
  assert.ok('private' in h, 'health 缺少 private 段');
  assert.ok('ready' in h.private);
  assert.ok('configured' in h.private);
});
