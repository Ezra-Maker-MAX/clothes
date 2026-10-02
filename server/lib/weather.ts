/**
 * 天气服务 —— 零配置可用 + 可选和风增强
 *
 * 定位优先级（解决「天气永远是上海」）：
 *   1. 前端 ?location=（用户在 App 设置里手动填的城市名 / 坐标）
 *   2. 环境变量 WEATHER_LOCATION（想固定城市时用）
 *   3. 请求方 IP 自动定位（ipwho.is，免费免 key）—— 手机/桌面都零配置生效
 *   4. 兜底上海
 *
 * 取数优先级：
 *   1. 和风天气（配了 WEATHER_API_KEY 时用，体感温度与中文描述更准）
 *   2. Open-Meteo（**免费免 key**，有坐标就能取真实温度 —— 所以不配任何 key 也有真天气）
 *   3. mock 24°C（既没 key 又定位失败时的最后一档，绝不白屏）
 *
 * 城市名来源：用户填的名字 > WEATHER_CITY > IP 定位城市名。
 * 关键点：mock 档也用定位到的城市名，界面不会再出现"上海"这种明显错误的地名。
 *
 * 参考：
 *   https://dev.qweather.com/docs/api/weather/weather-now/
 *   https://open-meteo.com/en/docs（无需注册）
 */
import type { WeatherSnapshot } from './types';

export interface QWeatherResult extends WeatherSnapshot {
  source: 'qweather' | 'open-meteo' | 'mock';
  city: string;
  /** 定位方式：client=用户指定 / env=环境变量固定 / ip=IP 自动定位 / default=默认兜底 */
  locatedBy: 'client' | 'env' | 'ip' | 'default';
}

/** 一次定位结果：坐标（用于免 key 天气）+ 展示城市名 + 和风可用的查询串 */
interface Place {
  lat?: number;
  lon?: number;
  /** 和风查询串：LocationID 或 "经度,纬度" */
  qweather?: string;
  city: string;
  locatedBy: QWeatherResult['locatedBy'];
}

// ------------------------------------------------------------------
// 缓存（IP 30 分钟 / 城市名与坐标 24 小时）—— 避免每次推荐都打外网
// ------------------------------------------------------------------
const CACHE_TTL_SHORT = 30 * 60 * 1000;
const CACHE_TTL_LONG = 24 * 60 * 60 * 1000;
const ipCache = new Map<string, { at: number; lat: number; lon: number; city: string }>();
const geoCache = new Map<string, { at: number; place: Place }>();
const wxCache = new Map<string, { at: number; wx: { tempC: number; feelsLike: number; condition: string } }>();

function cacheGet<T>(m: Map<string, { at: number } & T>, key: string, ttl: number): (T & { at: number }) | null {
  const hit = m.get(key);
  if (hit && Date.now() - hit.at < ttl) return hit;
  return null;
}

function cacheSet<T>(m: Map<string, { at: number } & T>, key: string, value: T, cap = 200): void {
  if (m.size > cap) {
    const oldest = m.keys().next().value;
    if (oldest !== undefined) m.delete(oldest);
  }
  m.set(key, { at: Date.now(), ...value });
}

/** 局域网/本机 IP 不定位（Vercel 上不会出现，本地开发兜底） */
function isPrivateIp(ip: string): boolean {
  return (
    ip === '127.0.0.1' ||
    ip === '::1' ||
    ip.startsWith('10.') ||
    ip.startsWith('192.168.') ||
    ip.startsWith('172.16.') ||
    /^f[cd]/.test(ip)
  );
}

/** 形如 "101010100"（和风 ID）或 "116.41,39.92"（坐标）—— 不用再解析成地名 */
function looksLikeLocationId(s: string): boolean {
  return /^[\d.]+(,[\d.]+)?$/.test(s.trim());
}

// ------------------------------------------------------------------
// 1) IP → 坐标 + 城市名（ipwho.is，免 key）
// ------------------------------------------------------------------
async function locateByIp(ip: string): Promise<{ lat: number; lon: number; city: string } | null> {
  const clean = ip.replace(/^::ffff:/, '').trim();
  if (!clean || isPrivateIp(clean)) return null;

  const hit = cacheGet(ipCache, clean, CACHE_TTL_SHORT);
  if (hit) return hit;

  try {
    const r = await fetch(`https://ipwho.is/${encodeURIComponent(clean)}`, {
      signal: AbortSignal.timeout(2500),
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const j = (await r.json()) as {
      success?: boolean; message?: string; city?: string;
      latitude?: number; longitude?: number;
    };
    if (j.success === false) throw new Error(j.message ?? 'ip lookup failed');
    const lat = Number(j.latitude);
    const lon = Number(j.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
    const v = { lat, lon, city: String(j.city ?? '').trim() || '你所在的城市' };
    cacheSet(ipCache, clean, v);
    return v;
  } catch (e) {
    console.warn('[weather] IP 定位失败：', e instanceof Error ? e.message : e);
    return null;
  }
}

// ------------------------------------------------------------------
// 2) 城市名 → 坐标（Open-Meteo Geocoding，免 key；填「北京」「Tokyo」都能用）
// ------------------------------------------------------------------
async function geocodeByName(name: string): Promise<Place | null> {
  const hit = cacheGet(geoCache, name, CACHE_TTL_LONG);
  if (hit) return hit.place;

  try {
    const r = await fetch(
      `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(name)}`
        + `&count=1&language=zh&format=json`,
      { signal: AbortSignal.timeout(3000) },
    );
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const j = (await r.json()) as {
      results?: Array<{ latitude: number; longitude: number; name?: string; admin1?: string; country?: string }>;
    };
    const hit0 = j.results?.[0];
    if (!hit0) return null;
    const place: Place = {
      lat: Number(hit0.latitude),
      lon: Number(hit0.longitude),
      qweather: `${Number(hit0.longitude).toFixed(2)},${Number(hit0.latitude).toFixed(2)}`,
      city: name,
      locatedBy: 'client',
    };
    cacheSet(geoCache, name, { place });
    return place;
  } catch (e) {
    console.warn('[weather] 城市解析失败：', e instanceof Error ? e.message : e);
    return null;
  }
}

// ------------------------------------------------------------------
// 3) 天气取数
// ------------------------------------------------------------------
/** WMO 天气代码 → 中文描述（Open-Meteo） */
const WMO_TEXT: Record<number, string> = {
  0: '晴', 1: '晴间多云', 2: '多云', 3: '阴',
  45: '雾', 48: '雾凇',
  51: '小毛毛雨', 53: '毛毛雨', 55: '大毛毛雨',
  56: '冻毛毛雨', 57: '冻毛毛雨',
  61: '小雨', 63: '中雨', 65: '大雨',
  66: '冻雨', 67: '冻雨',
  71: '小雪', 73: '中雪', 75: '大雪', 77: '雪粒',
  80: '阵雨', 81: '强阵雨', 82: '暴雨',
  85: '阵雪', 86: '强阵雪',
  95: '雷阵雨', 96: '雷阵雨伴冰雹', 99: '雷暴伴冰雹',
};

/** 和风 LocationID 查询（需 key）：返回真实体感温度，中文描述最准 */
async function fetchQWeather(query: string, key: string) {
  const r = await fetch(
    `https://devapi.qweather.com/v7/weather/now?location=${encodeURIComponent(query)}&key=${key}`,
    { signal: AbortSignal.timeout(4000) },
  );
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const j = (await r.json()) as { code?: string; now?: { temp?: string; feelsLike?: string; text?: string } };
  if (j.code !== '200' || !j.now) throw new Error(`code ${j.code}`);
  return {
    tempC: Number(j.now.temp ?? 24),
    feelsLike: Number(j.now.feelsLike ?? j.now.temp ?? 25),
    condition: j.now.text ?? '多云',
  };
}

/** Open-Meteo 查询（免 key，只要有坐标）：不配任何 key 也能拿真实天气 */
async function fetchOpenMeteo(lat: number, lon: number) {
  const key = `wx:${lat.toFixed(2)},${lon.toFixed(2)}`;
  const hit = cacheGet(wxCache, key, 30 * 60 * 1000);
  if (hit) return hit.wx;

  const r = await fetch(
    `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}`
      + `&current=temperature_2m,apparent_temperature,weather_code&timezone=auto`,
    { signal: AbortSignal.timeout(4000) },
  );
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const j = (await r.json()) as {
    current?: { temperature_2m?: number; apparent_temperature?: number; weather_code?: number };
  };
  if (!j.current) throw new Error('no current data');
  const wx = {
    tempC: Math.round(Number(j.current.temperature_2m ?? 24)),
    feelsLike: Math.round(Number(j.current.apparent_temperature ?? j.current.temperature_2m ?? 25)),
    condition: WMO_TEXT[Number(j.current.weather_code ?? 2)] ?? '多云',
  };
  cacheSet(wxCache, key, { wx });
  return wx;
}

// ------------------------------------------------------------------
// 对外主函数
// ------------------------------------------------------------------
export interface GetWeatherOpts {
  /** 显式位置：城市名 / 和风 LocationID / "经度,纬度" */
  location?: string;
  /** 展示用城市名（手动指定时前端会一起传） */
  city?: string;
  /** 请求方 IP，用于自动定位（handler 从 x-forwarded-for 取） */
  ip?: string;
}

/** 定位：决定"查哪儿" */
async function resolvePlace(opts: GetWeatherOpts): Promise<Place> {
  const key = process.env.WEATHER_API_KEY;
  const clientLoc = opts.location?.trim() ?? '';
  const envLoc = process.env.WEATHER_LOCATION?.trim() ?? '';
  const userCity = opts.city?.trim() ?? '';

  // ① 用户手动指定
  if (clientLoc) {
    const coord = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/.exec(clientLoc);
    if (coord) {
      const lon = Number(coord[1]);
      const lat = Number(coord[2]);
      return { lat, lon, qweather: `${lon.toFixed(2)},${lat.toFixed(2)}`, city: userCity, locatedBy: 'client' };
    }
    if (looksLikeLocationId(clientLoc)) {
      return { qweather: clientLoc, city: userCity, locatedBy: 'client' };
    }
    // 城市名：免 key 用 Open-Meteo 地理编码；有 key 也用它拿坐标作为免 key 兜底
    const geo = await geocodeByName(clientLoc);
    if (geo) return { ...geo, city: userCity || clientLoc, locatedBy: 'client' };
    return { qweather: clientLoc, city: userCity || clientLoc, locatedBy: 'client' };
  }

  // ② 环境变量固定城市
  if (envLoc) {
    if (looksLikeLocationId(envLoc)) {
      const coord = envLoc.includes(',')
        ? envLoc.split(',').map(Number) as [number, number]
        : null;
      return {
        lon: coord?.[0], lat: coord?.[1], qweather: envLoc,
        city: process.env.WEATHER_CITY?.trim() || '', locatedBy: 'env',
      };
    }
    const geo = await geocodeByName(envLoc);
    if (geo) return { ...geo, city: process.env.WEATHER_CITY?.trim() || envLoc, locatedBy: 'env' };
    return { qweather: envLoc, city: process.env.WEATHER_CITY?.trim() || envLoc, locatedBy: 'env' };
  }

  // ③ IP 自动定位
  if (opts.ip) {
    const hit = await locateByIp(opts.ip);
    if (hit) {
      return {
        lat: hit.lat, lon: hit.lon,
        qweather: `${hit.lon.toFixed(2)},${hit.lat.toFixed(2)}`,
        city: hit.city, locatedBy: 'ip',
      };
    }
  }

  // ④ 兜底
  return { qweather: '101020100', city: '上海', locatedBy: 'default', lat: 31.23, lon: 121.47 };
}

export async function getWeather(opts: GetWeatherOpts = {}): Promise<QWeatherResult> {
  const key = process.env.WEATHER_API_KEY;
  const place = await resolvePlace(opts);
  const city = place.city || opts.city?.trim() || '';

  // 和风优先（有 key 且能拿到它的查询串）
  if (key && place.qweather) {
    try {
      const w = await fetchQWeather(place.qweather, key);
      return { ...w, city, source: 'qweather', locatedBy: place.locatedBy };
    } catch (e) {
      console.warn('[weather] 和风失败，降级 Open-Meteo：', e instanceof Error ? e.message : e);
    }
  }

  // 免 key 兜底：有坐标就用 Open-Meteo 真实天气
  if (place.lat !== undefined && place.lon !== undefined) {
    try {
      const w = await fetchOpenMeteo(place.lat, place.lon);
      return { ...w, city, source: 'open-meteo', locatedBy: place.locatedBy };
    } catch (e) {
      console.warn('[weather] Open-Meteo 失败，降级 mock：', e instanceof Error ? e.message : e);
    }
  }

  return { tempC: 24, feelsLike: 25, condition: '多云', city: city || '上海', source: 'mock', locatedBy: place.locatedBy };
}

/** 供 /api/health 自检与排查（不发网络请求） */
export function weatherStatus() {
  return {
    keyConfigured: Boolean(process.env.WEATHER_API_KEY),
    fixedLocation: process.env.WEATHER_LOCATION || null,
    freeFallback: 'Open-Meteo（免 key）',
    ipGeoService: 'ipwho.is（免 key）',
    hint: process.env.WEATHER_API_KEY
      ? '已配和风 KEY：优先和风，失败自动降级 Open-Meteo 真实天气'
      : '未配和风 KEY：走 Open-Meteo 免费接口，按你的 IP/所填城市取真实温度；'
        + '想要更准的体感与中文描述可免费申请：https://dev.qweather.com/',
  };
}
