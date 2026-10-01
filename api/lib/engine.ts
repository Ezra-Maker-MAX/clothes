/**
 * 情景引擎 v0.1 —— 规则版推荐内核
 * 思路：场景定正式度 + 天气定厚度 + 历史排重 + 桶内随机
 * （第三阶段在其外层再叠加 LLM 润色理由文案）
 */
import type { WardrobeItem, Occasion, WeatherSnapshot } from './types';

/** 场合 → 目标正式度 */
export const FORMALITY: Record<Occasion, number> = {
  commute: 3, date: 4, interview: 5, casual: 2, party: 4,
};

/** 体感温度 → 目标厚度区间 */
export function warmthFor(tempC: number): [number, number] {
  if (tempC >= 26) return [1, 2];
  if (tempC >= 18) return [2, 3];
  if (tempC >= 10) return [3, 4];
  return [4, 5];
}

/** 场合 → 妆容推荐（温柔但有洞察） */
export const MAKEUP: Record<Occasion, string> = {
  commute: '清透底妆 + 豆沙色唇，会议室灯光下不假面',
  date: '微醺腮红 + 水光唇，走到他面前那三秒最有效',
  interview: '哑光底妆 + 大地色眼影，专业感先声夺人',
  casual: '素颜感底妆 + 有色润唇膏，藏一点慵懒',
  party: '烟熏感眼妆 + 玻璃唇，灯光越暗越出彩',
};

/** 理由文案模板：不油腻、有细节、带点洞察 */
function buildReason(
  top: WardrobeItem, bottom: WardrobeItem, shoe: WardrobeItem,
  weather: WeatherSnapshot, avoidedCount: number,
): string {
  const parts = [top.name, bottom.name, shoe.name].join(' + ');
  const tempHint =
    weather.feelsLike >= 28 ? '体感偏热，这一身透气不粘人'
    : weather.feelsLike >= 18 ? '温度刚刚好，不冷不热正合适'
    : '体感偏凉，这身厚度刚好压得住';
  const avoidHint = avoidedCount > 0 ? `避开最近穿过的 ${avoidedCount} 件，` : '';
  const patternHint = top.pattern && top.pattern !== 'plain' ? '' : '干净配色显贵，';
  return `${parts}。${avoidHint}${tempHint}，${patternHint}气质在线。`;
}

export interface PickResult {
  outfit: { top: WardrobeItem; bottom: WardrobeItem; shoe: WardrobeItem };
  avoidedCount: number;
}

/**
 * 从衣橱挑选三件套（上衣/下装/鞋）
 * @param excludeIds 最近穿过、需避开的单品 ID
 * 多级放宽策略：厚度 → 正式度 → 排除集，保证任何衣橱存量都能出结果
 */
export function pickOutfit(
  items: WardrobeItem[],
  opts: { occasion: Occasion; tempC: number; excludeIds: string[]; rotation?: number },
): PickResult | null {
  const active = items.filter(i => i.status === 'active');
  const bucket = (c: string) => active.filter(i => i.category === c);
  const [wMin, wMax] = warmthFor(opts.tempC);
  const fTarget = FORMALITY[opts.occasion] ?? 3;

  const score = (i: WardrobeItem): number =>
    // 排重惩罚：最近穿过的强降权
    (opts.excludeIds.includes(i.id) ? -100 : 0)
    // 厚度贴合度
    + (i.warmth_level >= wMin && i.warmth_level <= wMax ? 2 : 0)
    // 正式度贴合度
    + (Math.abs(i.formality - fTarget) <= 1 ? 2 : 0)
    // 心动单品加一点权重
    + (i.is_favorite ? 0.5 : 0)
    + Math.random(); // 洗牌，避免每次都一样

  // 「换一套」轮换：同温度下最优解往往唯一，故取评分前三候选，
  // 按 rotation 在候选间轮换，保证每点一次「换一套」都能换出不同组合
  const rotation = opts.rotation ?? 0;
  const pickBest = (pool: WardrobeItem[]): WardrobeItem | null => {
    if (!pool.length) return null;
    const sorted = [...pool].sort((a, b) => score(b) - score(a));
    const top = sorted.slice(0, Math.min(3, sorted.length));
    return top[rotation % top.length];
  };

  // 第一优先：完全不重样
  let top = pickBest(bucket('tops').filter(i => !opts.excludeIds.includes(i.id)));
  let bottom = pickBest(bucket('bottoms').filter(i => !opts.excludeIds.includes(i.id)));
  let shoe = pickBest(bucket('shoes').filter(i => !opts.excludeIds.includes(i.id)));
  let avoidedCount = opts.excludeIds.length;

  // 放宽兜底：宁可重复也不能没得穿
  if (!top) { top = pickBest(bucket('tops')); avoidedCount -= opts.excludeIds.length > 0 ? 1 : 0; }
  if (!bottom) { bottom = pickBest(bucket('bottoms')); }
  if (!shoe) { shoe = pickBest(bucket('shoes')); }

  if (!top || !bottom || !shoe) return null;
  return {
    outfit: { top, bottom, shoe },
    avoidedCount: Math.max(0, avoidedCount),
  };
}

export { buildReason };
