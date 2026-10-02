/**
 * LLM 润色服务（引擎 v0.2 外层叠加）
 *
 * 规则引擎先产出"底稿"（单品名 + 温度/排重提示），LLM 再按
 * 「嘴快心细的伴侣」人设润色成一句有洞察的推荐理由。
 * 任何失败（未配 KEY / 网络异常 / 超时）都返回 null，调用方降级回底稿——
 * 保证推荐永远有结果，润色只是加分项。
 *
 * ⚠️ 环境变量（Vercel Dashboard 或本地 .env）：
 *   LLM_API_KEY   OpenAI 兼容 API Key
 *   LLM_BASE_URL  默认 https://apihub.agnes-ai.com/v1
 *   LLM_MODEL     默认 agnes-2.5-flash
 */

/** 人设 system prompt：严格按项目文案规范（不油腻、有分寸、拒绝空话） */
const SYSTEM_PROMPT = `你是「衣念」App 的推荐理由撰稿人，人设是嘴快心细的伴侣：不油腻、有分寸，拒绝"这套很适合你"式的废话。
写作规则：
1. 一句话，30~55 字，中文，直接输出文案本身（不要引号、不要前缀、不要解释）；
2. 必须包含至少一个具体洞察：颜色关系、版型细节、温度体感、场合心机；
3. 口语但有分寸，可以轻微调侃，绝不油腻；
4. 禁用"适合""百搭""气质在线""彰显品味"这类空话收尾；
5. 不说教、不解释穿搭原理。`;

export interface PolishContext {
  ruleReason: string;      // 规则引擎底稿
  occasionLabel: string;   // 场景：日常通勤
  condition: string;       // 天气现象：多云
  feelsLike: number;       // 体感温度
  avoidedCount: number;    // 排重件数
}

function buildUserPrompt(ctx: PolishContext): string {
  const avoid = ctx.avoidedCount > 0 ? `已避开最近穿过的 ${ctx.avoidedCount} 件。` : '';
  return [
    `场景：${ctx.occasionLabel}；体感 ${ctx.feelsLike}°C、${ctx.condition}。${avoid}`,
    `底稿：${ctx.ruleReason}`,
    '请按人设改写这一句推荐理由。',
  ].join('\n');
}

/** 调 LLM 润色；失败返回 null（调用方降级底稿） */
export async function polishReason(ctx: PolishContext): Promise<string | null> {
  const key = process.env.LLM_API_KEY;
  if (!key) return null;
  const baseUrl = (process.env.LLM_BASE_URL ?? 'https://apihub.agnes-ai.com/v1').replace(/\/+$/, '');
  const model = process.env.LLM_MODEL ?? 'agnes-2.5-flash';

  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), 8000); // Vercel maxDuration 10s，留 buffer
  try {
    const r = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      signal: ac.signal,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: buildUserPrompt(ctx) },
        ],
        temperature: 0.9,
        // ⚠️ agnes-2.5-flash 是推理模型（响应含 reasoning_content），
        // max_tokens 必须给足推理+回复的空间，太小会 finish_reason=length 且 content 为空
        max_tokens: 1000,
      }),
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const j = (await r.json()) as {
      choices?: Array<{ message?: { content?: string }; finish_reason?: string }>;
    };
    const choice = j.choices?.[0];
    const text = choice?.message?.content?.trim();
    if (!text) {
      console.warn(
        '[llm] 空文案（finish_reason=%s），降级规则文案',
        choice?.finish_reason ?? 'unknown',
      );
      return null;
    }
    // 过长（LLM 跑飞）视为失败
    if (text.length > 80) return null;
    return text;
  } catch (e) {
    console.warn('[llm] 润色失败，降级规则文案：', e instanceof Error ? e.message : e);
    return null;
  } finally {
    clearTimeout(timer);
  }
}
