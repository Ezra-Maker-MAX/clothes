/**
 * /api/import-order —— 订单文本导入（P2 降级方案）
 *
 * 背景：淘宝 OAuth 订单拉取个人开发者拿不到授权，退而求其次——
 * 用户在淘宝「我的订单」把商品名复制/粘贴成多行文本，这里解析并批量建单品。
 *
 * POST body: { userId, text }
 *   → 按行解析：剔除空行/纯数字行/促销噪声行，行内提取 {名称, 价格}
 *   → 关键词猜分类（猜不到默认 tops，客户端可再编辑）
 *   → 批量 INSERT（source='import'，无图，emoji 占位）
 *   → 返回 { imported, items: [{id, name, category, guessed}] }
 *
 * 解析是宽容式的：淘宝分享文本格式多变（带价格/数量/店铺名前缀），
 * 目标是「多数行直接可用，个别行手动改」，不追求 100% 精确。
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getDb, uuid, ensureSchema } from '../_lib/db';
import { cors, ok, fail } from '../_lib/http';

/** 关键词 → 引擎分类（词序即优先级，越具体越靠前） */
const CATEGORY_RULES: Array<{ key: string; words: string[] }> = [
  { key: 'dresses',     words: ['连衣裙', '长裙', '短裙连衣裙', 'one piece'] },
  { key: 'outerwear',   words: ['外套', '大衣', '羽绒服', '棉服', '夹克', '风衣', '西装', '开衫', '马甲', '披肩'] },
  { key: 'shoes',       words: ['鞋', '靴', '拖鞋', '凉鞋', '高跟鞋', '运动鞋', '板鞋', '乐福', '穆勒'] },
  { key: 'bags',        words: ['包', '袋', '挎包', '背包', '钱包', '卡包'] },
  { key: 'accessories', words: ['帽子', '围巾', '丝巾', '项链', '耳环', '戒指', '手链', '手表', '腰带', '袜子', '发'] },
  { key: 'bottoms',     words: ['裤', '牛仔', '半身裙', '短裙', '裙'] },
  { key: 'tops',        words: ['衫', 'tee', 'T恤', 't恤', '上衣', '衬衫', '卫衣', '毛衣', '针织', '背心', '吊带'] },
];

function guessCategory(name: string): { key: string; guessed: boolean } {
  const lower = name.toLowerCase();
  for (const rule of CATEGORY_RULES) {
    for (const w of rule.words) {
      if (lower.includes(w.toLowerCase())) return { key: rule.key, guessed: false };
    }
  }
  return { key: 'tops', guessed: true };
}

/** 行噪声：这些行直接丢 */
const NOISE = /(订单|商品|总价|实付|付款|发货|收货|退款|快递|运费|优惠券|红包|合计|店铺|客服|售后|评价|复制|打开|淘宝|天猫|淘口令|https?:\/\/|¥\s*$)/i;

/** 从一行里提取 {name, price}；无法提取返回 null */
function parseLine(raw: string): { name: string; price: number | null } | null {
  let line = raw.trim();
  if (line.length < 2 || line.length > 60) return null;
  if (NOISE.test(line)) return null;
  if (/^[\d\s.,，。¥￥元+-]+$/.test(line)) return null; // 纯数字/货币行

  // 提取行内价格：¥xx / xx元 / 结尾数字（容忍 12.9 / 1,299 等写法）
  let price: number | null = null;
  const pm = line.match(/[¥￥]\s*([\d.,]+)|([\d.,]+)\s*元|(?:^|\s)([\d.,]{2,})\s*$/);
  if (pm) {
    const num = pm[1] ?? pm[2] ?? pm[3];
    const v = Number(String(num).replace(/,/g, ''));
    if (Number.isFinite(v) && v > 0 && v < 100000) price = v;
  }

  // 名称清洗：去数量 x1/×1、去价格片段、去首尾标点
  let name = line
    .replace(/[\[【(（]?\s*[x×✕]\s*\d+\s*[\]】)）]?/gi, '')   // x1 / ×2
    .replace(/[¥￥]\s*[\d.,]+|[\d.,]+\s*元/g, '')
    .replace(/^[\s\-—·:：|｜]+|[\s\-—·:：|｜]+$/g, '')
    .trim();
  // 价格数字出现在行尾已被吃掉；再把孤立的长数字串去掉（订单号碎片）
  name = name.replace(/(^|\s)\d{8,}(\s|$)/g, ' ').replace(/\s{2,}/g, ' ').trim();
  if (name.length < 2) return null;
  return { name, price };
}

export async function handler(req: VercelRequest, res: VercelResponse) {
  cors(req, res);
  const db = getDb();

  if (req.method !== 'POST') return fail(res, 405, `不支持的请求方法: ${req.method}`);

  const b = req.body ?? {};
  if (!b.userId || !b.text) return fail(res, 400, 'userId 与 text 必填');
  const text = String(b.text);
  if (text.length > 20000) return fail(res, 413, '文本太长，一次粘一批就好');

  const lines = text.split(/\r?\n/);
  const parsed: Array<{ name: string; price: number | null }> = [];
  const seen = new Set<string>();
  for (const l of lines) {
    const p = parseLine(l);
    if (p && !seen.has(p.name)) {
      seen.add(p.name); // 同名去重（订单里同款多色常见）
      parsed.push(p);
    }
  }
  if (!parsed.length) {
    return fail(res, 422, '没解析出商品名：确认粘贴的是订单里的商品行，每行一个');
  }
  if (parsed.length > 100) return fail(res, 413, '一次最多 100 件，分批来');

  if (!db) {
    // mock：返回解析结果但不落库，前端提示演示模式
    return ok(res, {
      mode: 'mock', imported: 0,
      parsed: parsed.map(p => ({ ...p, ...guessCategory(p.name) })),
      message: 'mock 模式：已解析（未落库）',
    });
  }

  try {
    await ensureSchema(); // image_urls/pinned 等新列就位
    const items: Array<{ id: string; name: string; category: string; guessed: boolean }> = [];
    for (const p of parsed) {
      const { key, guessed } = guessCategory(p.name);
      const id = uuid();
      await db.execute({
        sql: `INSERT INTO wardrobe_items
              (id, user_id, name, image_url, category, price, pinned, source, wear_count)
              VALUES (?,?,?,?,?,?,0,'import',0)`,
        args: [id, String(b.userId), p.name,
               `https://placehold.co/400x533?text=${encodeURIComponent(p.name.slice(0, 8))}`,
               key, p.price],
      });
      items.push({ id, name: p.name, category: key, guessed });
    }
    return ok(res, { mode: 'turso', imported: items.length, items });
  } catch (e) {
    return fail(res, 500, '导入失败', e instanceof Error ? e.message : String(e));
  }
}
