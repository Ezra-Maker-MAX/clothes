/**
 * 共享类型定义（前端联调时 Flutter 侧按此结构建模）
 */

export type Category = 'tops' | 'bottoms' | 'dresses' | 'outerwear' | 'shoes' | 'bags' | 'accessories';

export type Occasion = 'commute' | 'date' | 'interview' | 'casual' | 'party';

export interface WardrobeItem {
  id: string;
  user_id: string;
  name: string;
  image_url: string;
  thumbnail_url?: string | null;
  category: Category;
  sub_category?: string | null;
  color_name?: string | null;
  color_hex?: string | null;
  color_family?: string | null;
  pattern?: string | null;
  warmth_level: number;
  formality: number;
  wear_count: number;
  last_worn_at?: string | null;
  is_favorite?: number;
  status: 'active' | 'archived';
}

/** 推荐结果结构（outfit_json 列的 JSON 契约） */
export interface OutfitRecommendation {
  items: {
    top: WardrobeItem | MockItem;
    bottom: WardrobeItem | MockItem;
    shoe: WardrobeItem | MockItem;
  };
  reason: string;
  makeup: string;
  weather: WeatherSnapshot;
}

export interface WeatherSnapshot {
  tempC: number;
  feelsLike: number;
  condition: string; // 多云 / 晴 / 小雨 ...
  city?: string;    // 定位城市（和风天气地名，仅展示用）
}

/** 历史记录创建入参 */
export interface HistoryCreateInput {
  userId: string;
  itemIds: string[];
  wornDate?: string;
  occasion: Occasion;
  weatherSnapshot?: WeatherSnapshot;
  rating?: number;
  feedback?: string;
}

export interface MockItem {
  id: string;
  name: string;
  image_url: string;
  color_name: string;
  pattern?: string;
}
