/**
 * 私密图取流代理的鉴权与路径白名单测试
 *
 * 这个接口是全项目唯一能读出私密图的途径，两道防线必须守住：
 *   1. Bearer token 校验 —— 防止任何人用直链（私有 blob 直链虽然403，
 *      但接口本身不能成为绕过鉴权的后门）
 *   2. pathname 白名单 —— **最重要的一条**。若没有它，这个接口就等于
 *      一个「用服务端凭据读任意 blob」的读取器：构造 pathname=wardrobe/xxx
 *      就能拿到衣橱图，构造../../ 之类还可能读到 store 内其他对象。
 *      私密数据被圈在 private/ 前缀内，正是靠这一条。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.PRIVATE_MODE_PASSWORD = 'unit-test-pass-1234';
process.env.PRIVATE_BLOB_READ_WRITE_TOKEN = 'fake-token-for-pathname-guard-test';

const { handler } = await import('../server/handlers/private-image.ts');
const { issuePrivateToken } = await import('../server/lib/private-token.ts');
const TOKEN = issuePrivateToken();

function makeRes() {
  const r = {
    statusCode: 0,
    body: null,
    written: 0,
    headers: {},
    setHeader(k, v) {
      r.headers[k.toLowerCase()] = v;
    },
    status(code) {
      r.statusCode = code;
      return r;
    },
    json(obj) {
      r.body = obj;
      return r;
    },
    write(chunk) {
      r.written += chunk.length;
      return true;
    },
    end() {
      r.ended = true;
      return r;
    },
  };
  return r;
}

function get(pathname, { token = TOKEN, method = 'GET' } = {}) {
  return {
    method,
    headers: token ? { authorization: `Bearer ${token}` } : {},
    query: pathname === undefined ? {} : { pathname },
    body: {},
  };
}

/** 只看状态码，不关心 body 的流式失败（无真实 Blob 凭据时取流必然失败） */
async function statusOf(pathname, opts) {
  const res = makeRes();
  await handler(get(pathname, opts), res);
  return res.statusCode;
}

test('缺令牌 → 401，绝不放行', async () => {
  assert.equal(await statusOf('private/a.jpg', { token: '' }), 401);
  assert.equal(await statusOf('private/a.jpg', { token: null }), 401);
});

test('伪造/过期令牌 → 401', async () => {
  assert.equal(await statusOf('private/a.jpg', { token: 'garbage' }), 401);
  const wrong = issuePrivateToken().replace(/.$/, 'x');
  assert.equal(await statusOf('private/a.jpg', { token: wrong }), 401);
});

test('合法令牌 + 合法路径：鉴权放行（后续取流失败属预期，无真实 Blob 凭据）', async () => {
  const code = await statusOf('private/pv_123.jpg');
  // 走到取流阶段说明鉴权+白名单都过了；无真实凭据时 404/500 都算到达
  assert.ok(
    code === 404 || code === 500,
    `应通过鉴权进入取流阶段，实际 ${code}（401/400 说明前置校验误杀）`,
  );
});

test('白名单：拒绝非 private/ 前缀（不能读衣橱公开图）', async () => {
  assert.equal(await statusOf('wardrobe/item.jpg'), 400);
  assert.equal(await statusOf('private-x/a.jpg'), 400);
  assert.equal(await statusOf('evil/a.jpg'), 400);
});

test('白名单：拒绝路径穿越', async () => {
  assert.equal(await statusOf('private/../../etc/passwd'), 400);
  assert.equal(await statusOf('private/../wardrobe/x.jpg'), 400);
  assert.equal(await statusOf('private//../x.jpg'), 400);
});

test('白名单：拒绝绝对路径与空值', async () => {
  assert.equal(await statusOf('/private/a.jpg'), 400);
  assert.equal(await statusOf(''), 400);
  assert.equal(await statusOf(undefined), 400);
});

test('非 GET 方法 → 405', async () => {
  const res = makeRes();
  await handler(get('private/a.jpg', { method: 'POST' }), res);
  assert.equal(res.statusCode, 405);
});

test('未配置私密 store 时 → 503 且给出可操作指引（不是静默失败）', async () => {
  const backup = process.env.PRIVATE_BLOB_READ_WRITE_TOKEN;
  delete process.env.PRIVATE_BLOB_READ_WRITE_TOKEN;
  const res = makeRes();
  await handler(get('private/a.jpg'), res);
  assert.equal(res.statusCode, 503);
  assert.ok(
    /Private|PRIVATE_BLOB_/.test(res.body.error),
    `503 提示应包含配置指引，实际：${res.body.error}`,
  );
  process.env.PRIVATE_BLOB_READ_WRITE_TOKEN = backup;
});
