/**
 * 私密会话令牌回归测试（node:test，零依赖，直接 `npm test` 跑）
 *
 * 为什么这几个必须有测试：private-token 是**整个私密空间的鉴权底座**——
 * /api/private-profile（围度/肤色/部位图元数据）与 /api/private-image（高清图取流）
 * 全靠它挡。一旦 HMAC 计算或过期判断被改坏，私密数据就门户大开，而这种改动
 * 在 review 时极容易漏看（几行crypto 调用，看起来无害）。
 *
 * 覆盖四个真实失效场景：
 *   1. 正常签发→校验通过
 *   2. 过期 token 被拒
 *   3. 篡改签名/载荷被拒
 *   4. 换密码（改环境变量）后旧 token 全部失效
 * 外加两条边界：未配置密码时不签发、空 token 不通过。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

const SECRET = 'test-secret-for-token-suite';

// 被测模块在 import 时就绑定 process.env，故用动态 import 在设好变量后再加载
process.env.PRIVATE_MODE_PASSWORD = SECRET;
const { issuePrivateToken, verifyPrivateToken, tokenOf } = await import(
  '../server/lib/private-token.ts'
);

test('正常签发的 token 能通过校验', () => {
  const t = issuePrivateToken();
  assert.ok(t, '应签发出token');
  assert.equal(verifyPrivateToken(t), true);
});

test('默认有效期为 7 天，且与 1 小时显式值行为一致', () => {
  const week = issuePrivateToken();
  const hour = issuePrivateToken(1);
  assert.ok(week && hour);
  assert.equal(verifyPrivateToken(week), true);
  assert.equal(verifyPrivateToken(hour), true);
  // 载荷里的过期时间戳应落在「现在 ~ 7 天内」
  const exp = Number(week.split('.')[0]);
  const sevenDays = 7 * 24 * 3600_000;
  const diff = exp - Date.now();
  assert.ok(diff > 0 && diff <= sevenDays, `7 天 token 剩余有效期应在 0~7 天内，实际 ${diff}ms`);
});

test('过期 token 被拒', () => {
  // -1 小时 = 已过期 1 小时
  const expired = issuePrivateToken(-1);
  assert.ok(expired, '即使已过期也照常签发（判断在校验侧）');
  assert.equal(verifyPrivateToken(expired), false);
});

test('篡改签名的 token 被拒', () => {
  const t = issuePrivateToken();
  assert.ok(t);
  const dot = t.indexOf('.');
  const exp = t.slice(0, dot);
  const sig = t.slice(dot + 1);
  // 签名末位改一位
  const flipped = sig.slice(0, -1) + (sig.endsWith('a') ? 'b' : 'a');
  assert.equal(verifyPrivateToken(`${exp}.${flipped}`), false);
});

test('篡改过期时间戳的 token 被拒（把 1 小时改成 10 年不能延寿）', () => {
  const t = issuePrivateToken(1);
  assert.ok(t);
  const sig = t.slice(t.indexOf('.') + 1);
  const farFuture = Date.now() + 10 * 365 * 24 * 3600_000;
  assert.equal(verifyPrivateToken(`${farFuture}.${sig}`), false);
});

test('结构性垃圾输入不抛异常，一律判否', () => {
  for (const bad of ['', '.', 'abc', '123', '123.', '.456', 'notatoken', 'null']) {
    assert.equal(verifyPrivateToken(bad), false, `输入 ${JSON.stringify(bad)} 应判否`);
  }
  assert.equal(verifyPrivateToken(null), false);
  assert.equal(verifyPrivateToken(undefined), false);
});

test('换密码后旧 token 全部失效（改环境变量 = 全员下线）', () => {
  const old = issuePrivateToken();
  assert.equal(verifyPrivateToken(old), true);
  process.env.PRIVATE_MODE_PASSWORD = 'a-totally-different-secret';
  assert.equal(verifyPrivateToken(old), false, '密码一改，旧 token 必须立刻失效');
  // 复原，避免影响后续用例
  process.env.PRIVATE_MODE_PASSWORD = SECRET;
});

test('未配置密码时不签发任何 token', () => {
  const backup = process.env.PRIVATE_MODE_PASSWORD;
  process.env.PRIVATE_MODE_PASSWORD = '   ';
  assert.equal(issuePrivateToken(), null);
  assert.equal(verifyPrivateToken('123.abc'), false);
  process.env.PRIVATE_MODE_PASSWORD = backup;
});

test('tokenOf：Authorization header 优先于 body', () => {
  assert.equal(
    tokenOf({ headers: { authorization: 'Bearer from-header' }, body: { token: 'from-body' } }),
    'from-header',
  );
  // 大小写不敏感
  assert.equal(tokenOf({ headers: { authorization: 'bearer lower' } }), 'lower');
  // 无 header 时退回 body
  assert.equal(tokenOf({ body: { token: 'from-body' } }), 'from-body');
  // 都没有 → 空串
  assert.equal(tokenOf({}), '');
});

test('tokenOf：拒绝把令牌放在 URL query 上不算取到值（防泄漏设计意图）', () => {
  // tokenOf 只认 header / body；query 里的 token 不会被采用，
  // 这样即使误把令牌拼进 URL，也不会被服务端当作有效凭证
  assert.equal(tokenOf({ query: { token: 'leaked-in-url' } }), '');
});
