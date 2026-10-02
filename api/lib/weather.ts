/**
 * 和风天气（QWeather）实时天气服务
 *
 * ⚠️ 环境变量（Vercel Dashboard 或本地 .env）：
 *   WEATHER_API_KEY    和风天气 API Key（devapi 免费版即可）
 *   WEATHER_LOCATION   默认城市 ID，如上海 101020100（location 也可由前端 ?location= 传入）
 *   WEATHER_CITY       展示用城市名（如「上海」）
 *
 * 未配置 KEY、或接口异常时，自动降级为 mock 天气（24°C / 体感25°C / 多云），
 * 保证「先跑通」阶段推荐引擎仍有真实可用的温度输入，绝不白屏。
 *
 * 参考：https://dev.qweather.com/docs/api/weather/weather-now/
 */
import type { WeatherSnapshot } from './types';

export interface QWeatherResult extends WeatherSnapshot {
  source: 'qweather' | 'mock';
  city: string;
}

const mockWeather = (city = '上海'): QWeatherResult => ({
  tempC: 24,
  feelsLike: 25,
  condition: '多云',
  city,
  source: 'mock',
});

/**
 * 获取实时天气。
 * @param location 和风城市 ID（如 101020100）或 "经度,纬度"
 * @param city     展示用城市名（落到 WeatherSnapshot 仅用于前端展示）
 */
export async function getWeather(opts: { location?: string; city?: string } = {}): Promise<QWeatherResult> {
  const key = process.env.WEATHER_API_KEY;
  const location = opts.location ?? process.env.WEATHER_LOCATION ?? '101020100';
  const cityName = opts.city ?? process.env.WEATHER_CITY ?? '上海';

  if (!key) return mockWeather(cityName);

  try {
    const url = `https://devapi.qweather.com/v7/weather/now?location=${encodeURIComponent(
      location,
    )}&key=${key}`;
    // ⚠️ 必须带超时：recommend 每个请求（含缓存命中路径）都先 await getWeather，
    // 和风 API 挂起时会拖满 Vercel maxDuration 被强杀 → 客户端 30s 超时。
    // 4s 拿不到就降级 mock，绝不拖累主链路。
    const r = await fetch(url, { signal: AbortSignal.timeout(4000) });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const j = (await r.json()) as { code?: string; now?: { temp?: string; feelsLike?: string; text?: string } };
    if (j.code !== '200' || !j.now) throw new Error(`code ${j.code}`);
    return {
      tempC: Number(j.now.temp ?? 24),
      feelsLike: Number(j.now.feelsLike ?? j.now.temp ?? 25),
      condition: j.now.text ?? '多云',
      city: cityName,
      source: 'qweather',
    };
  } catch (e) {
    // 接失败也不阻断推荐：降级 mock + 附带原因便于排查
    console.warn('[weather] 和风天气获取失败，降级 mock：', e instanceof Error ? e.message : e);
    return { ...mockWeather(cityName), source: 'mock' };
  }
}
