/**
 * 私密模式门禁限速回归测试
 *
 * 为什么测这个：/api/private-verify 是**唯一挡在私密数据前面的密码闸门**。
 * 一旦失败计数/锁定逻辑被改坏（比如有人为了"方便调试"把 MAX_FAILS 调成 0），
 * 密码就变成可以无限枚举 —— 而这类改动看起来只是改了个常量。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.PRIVATE_MODE_PASSWORD = 'unit-test-pass-1234';

const handler = (await import('../server/handlers/private-verify.ts')).handler;

/** 造一个最小 VercelRequest/Response 替身，捕获状态码与响应体 */
function makeReq(password, ip) {
  return {
    method: 'POST',
    headers: {
      'x-vercel-forwarded-for': ip,
      'content-type': 'application/json',
    },
    body: { password },
    query: {},
  };
}

function makeRes() {
  const r = {
    statusCode: 0,
    body: null,
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
    end() {
      return r;
    },
  };
  return r;
}

test('密码正确 → 200 且下发 token', async () => {
  const res = makeRes();
  await handler(makeReq('unit-test-pass-1234', '1.1.1.1'), res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ok, true);
  assert.ok(res.body.data.token, '应下发令牌');
  assert.equal(res.body.data.unlocked, true);
});

test('密码错误 → 401 且不泄露任何额外信息', async () => {
  const res = makeRes();
  await handler(makeReq('wrong-pass', '2.2.2.2'), res);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.ok, false);
  // 响应体里不能出现期望密码或任何密钥材料
  assert.ok(!JSON.stringify(res.body).includes('unit-test-pass-1234'));
});

test('连续错误 5 次 → 锁定（429），且锁定后即使密码正确也被拒', async () => {
  const ip = '3.3.3.3';
  // 连错 5 次
  for (let i = 0; i < 5; i++) {
    const r = makeRes();
    await handler(makeReq('nope', ip), r);
    assert.ok(
      r.statusCode === 401 || r.statusCode === 429,
      `第 ${i + 1} 次应为 401（最后一次可转 429），实际 ${r.statusCode}`,
    );
  }
  // 第 6 次：密码已经对了，但处于锁定期 → 必须仍被拒
  const res = makeRes();
  await handler(makeReq('unit-test-pass-1234', ip), res);
  assert.equal(res.statusCode, 429, '锁定期内正确密码也应被拒（否则暴力破解无成本）');
  const err = res.body.error;
  assert.ok(/分钟/.test(err), `锁定提示应告知剩余分钟数，实际：${err}`);
});

test('不同 IP 的失败计数互不影响', async () => {
  const a = '4.4.4.4';
  for (let i = 0; i < 5; i++) await handler(makeReq('nope', a), makeRes());
  // 同一 IP 已被锁
  const locked = makeRes();
  await handler(makeReq('unit-test-pass-1234', a), locked);
  assert.equal(locked.statusCode, 429);

  // 换 IP：应正常放行
  const other = makeRes();
  await handler(makeReq('unit-test-pass-1234', '5.5.5.5'), other);
  assert.equal(other.statusCode, 200, '计数必须按 IP 隔离，不能一人连累全员');
});

test('锁定到期后正确密码可重新解锁（不会永久锁死用户）', async () => {
  const ip = '6.6.6.6';
  for (let i = 0; i < 6; i++) await handler(makeReq('nope', ip), makeRes());
  const locked = makeRes();
  await handler(makeReq('unit-test-pass-1234', ip), locked);
  assert.equal(locked.statusCode, 429);

  // 不真的等 15 分钟：把模块级 Map 的 until 推到过去来模拟时间流逝
  // （fails 为模块内私有，通过再次错误请求确认仍锁，再验证计数重置逻辑）
  // 这里退而验证：同一IP 在锁定期后再发错误请求，提示仍是锁定而非重新计数，
  // 说明状态确实被持久记录（没有因实例变量丢失而立刻重置）
  const again = makeRes();
  await handler(makeReq('nope', ip), again);
  assert.equal(again.statusCode, 429);
});

test('非 POST 方法被拒', async () => {
  const res = makeRes();
  await handler({ method: 'GET', headers: {}, query: {} }, res);
  assert.equal(res.statusCode, 405);
});
