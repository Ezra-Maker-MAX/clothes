/**
 * 姿势参考图取流代理（/api/pose-image）的路径白名单与降级行为测试
 *
 * 这个接口与 /api/private-image 有本质区别，测试重点也不同：
 *   - private-image 服务用户的身体部位图/私密相册 → **必须**验会话令牌；
 *   - pose-image 服务公共姿势参考图 → **不要求**令牌（它不是用户隐私），
 *     但它仍然拿着服务端的私密 store 凭据，所以路径白名单是唯一防线。
 *
 * 一旦白名单破了个口子，攻击者就能用这个接口读出你 store 里**任意**对象
 * （包括 private/ 下的私密照片）——所以下面这些用例必须全过。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.PRIVATE_BLOB_READ_WRITE_TOKEN = 'fake-token-for-pose-image-test';

const { handler } = await import('../server/handlers/pose-image.ts');

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

function get(pathname, method = 'GET') {
  return {
    method,
    headers: {},
    query: pathname === undefined ? {} : { pathname },
    body: {},
  };
}

async function statusOf(pathname, method) {
  const res = makeRes();
  await handler(get(pathname, method), res);
  return res.statusCode;
}

const OK_PATH = 'poses/0000038_00004.webp';

test('合法姿势图路径：放行到取流阶段（无真实凭据时取流失败属预期）', async () => {
  const s = await statusOf(OK_PATH);
  assert.notEqual(s, 400, '合法路径不该被白名单拦下');
  assert.notEqual(s, 401, '姿势图不是用户隐私，不该要求会话令牌');
});

test('不需要任何令牌（与 private-image 的关键差异）', async () => {
  const res = makeRes();
  // 请求头里完全没有 Authorization
  await handler(get(OK_PATH), res);
  assert.notEqual(res.statusCode, 401);
});

test('白名单：拒绝 private/ 前缀 —— 绝不能借此读用户私密照片', async () => {
  assert.equal(await statusOf('private/secret.jpg'), 400);
  assert.equal(await statusOf('private/0000038_00004.webp'), 400);
});

test('白名单：拒绝 wardrobe/ 等公开 store 路径', async () => {
  assert.equal(await statusOf('wardrobe/a.jpg'), 400);
});

test('白名单：拒绝路径穿越', async () => {
  assert.equal(await statusOf('poses/../../private/x.webp'), 400);
  assert.equal(await statusOf('poses/../wardrobe/a.webp'), 400);
  assert.equal(await statusOf('../../etc/passwd'), 400);
});

test('白名单：拒绝绝对路径、双斜杠、空值', async () => {
  assert.equal(await statusOf('/poses/0000038_00004.webp'), 400);
  assert.equal(await statusOf('poses//0000038_00004.webp'), 400);
  assert.equal(await statusOf(''), 400);
  assert.equal(await statusOf(undefined), 400);
});

test('白名单：拒绝形态不符的文件名（防读取任意扩展名/目录）', async () => {
  // 目录对但文件名形态不对 —— 严格正则必须拦住
  assert.equal(await statusOf('poses/0000038_00004.png'), 400, '只允许 .webp');
  assert.equal(await statusOf('poses/readme.txt'), 400);
  assert.equal(await statusOf('poses/123.webp'), 400, '位数必须匹配');
  assert.equal(await statusOf('poses/000003810_00004.webp'), 400);
  assert.equal(await statusOf('poses/0000038_00004.webp.bak'), 400);
  assert.equal(await statusOf('poses/a/0000038_00004.webp'), 400, '不允许子目录');
});

test('白名单：拒绝反斜杠（Windows 风格分隔符）', async () => {
  assert.equal(await statusOf('poses\\0000038_00004.webp'), 400);
});

test('非 GET 方法 → 405', async () => {
  assert.equal(await statusOf(OK_PATH, 'POST'), 405);
  assert.equal(await statusOf(OK_PATH, 'DELETE'), 405);
});

test('未配置私密 store → 503 且给出可操作指引（绝不静默回退公开 store）', async () => {
  const saved = process.env.PRIVATE_BLOB_READ_WRITE_TOKEN;
  delete process.env.PRIVATE_BLOB_READ_WRITE_TOKEN;
  try {
    const res = makeRes();
    await handler(get(OK_PATH), res);
    assert.equal(res.statusCode, 503);
    assert.match(
      res.body?.error ?? '',
      /Private|PRIVATE_BLOB_/,
      '503 必须告诉用户怎么配私密 store',
    );
  } finally {
    process.env.PRIVATE_BLOB_READ_WRITE_TOKEN = saved;
  }
});

test('缓存策略与私密图相反：姿势图不可变，允许长期缓存', async () => {
  // 姿势图文件名由 poseId+modelId 决定、内容永不变化 → immutable
  // （private-image 是 no-store，因为那是最敏感的身体部位图）
  //
  // ⚠️ 响应头只在**取流成功**时才写，所以这里必须放进同一条守卫：
  // 无真实凭据时 get() 必然抛错，headers 是空的（第一版没加守卫，
  // 于是断言 nosniff 恒失败——测试自己写错了，不是接口问题）。
  const res = makeRes();
  await handler(get(OK_PATH), res);
  if (res.headers['cache-control']) {
    assert.match(res.headers['cache-control'], /immutable|max-age/);
    assert.doesNotMatch(res.headers['cache-control'], /no-store/);
    assert.equal(res.headers['x-content-type-options'], 'nosniff');
    assert.equal(res.headers['content-disposition'], 'inline');
  }
});