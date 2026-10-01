// 数据模型 —— 与后端 /api 契约对齐（见 api/lib/types.ts）
//
// 第二阶段为数据模拟：字段与后端一致，第三阶段联调时
// 只需把 ApiClient 切到真实 baseUrl，模型无需改动。
import 'package:flutter/material.dart';

class WeatherInfo {
  const WeatherInfo({
    required this.tempC,
    required this.feelsLike,
    required this.condition,
    required this.label,
    required this.city,
  });

  final int tempC;      // 实时温度
  final int feelsLike;  // 体感温度
  final String condition; // 天气现象：多云/晴/小雨
  final String label;   // 暖色标签文案：「舒适温度」
  final String city;    // 定位城市（和风天气 API 地名）

  factory WeatherInfo.mock() => const WeatherInfo(
        tempC: 24,
        feelsLike: 25,
        condition: '多云',
        label: '舒适温度',
        city: '上海',
      );
}

/// 单品展示模型（对应 wardrobe_items 行 + 前端展示字段）
class ItemInfo {
  const ItemInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.categoryLabel,
    this.imageUrl,
    this.colorName,
  });

  final String id;            // 单品唯一 ID（衣橱落库后由后端返回，acceptOutfit 据此写历史）
  final String name;
  final String categoryLabel; // 上衣 / 裤装 / 鞋子
  final String emoji;         // 第二阶段占位渲染；有 imageUrl 时优先网络图
  final String? imageUrl;     // Vercel Blob URL（第三阶段衣橱上传后回填）
  final String? colorName;

  /// 图卡底色：按分类给莫兰迪渐变
  List<Color> get gradient {
    switch (categoryLabel) {
      case '上衣':
        return const [Color(0xFFF3ECE1), Color(0xFFE9DCC9)];
      case '裤装':
        return const [Color(0xFFE3EBF3), Color(0xFFD3E0EC)];
      case '裙装':
        return const [Color(0xFFEFE6F0), Color(0xFFE2D3E6)];
      case '外套':
        return const [Color(0xFFE7E9E4), Color(0xFFD5D9D2)];
      case '配饰':
        return const [Color(0xFFFBEFE3), Color(0xFFF3DFC9)];
      default:
        return const [Color(0xFFF6E8E4), Color(0xFFEFD6D0)];
    }
  }
}

/// 今日推荐（对应 /api/recommend 返回的 outfit_json）
class OutfitRecommendation {
  const OutfitRecommendation({
    required this.occasion,
    required this.occasionLabel,
    required this.top,
    required this.bottom,
    required this.shoe,
    required this.reason,
    required this.makeup,
    required this.weather,
  });

  final String occasion;      // 场景键：commute/date/interview/casual/party（acceptOutfit 写入历史用）
  final String occasionLabel; // 场景标签：日常通勤
  final ItemInfo top;
  final ItemInfo bottom;
  final ItemInfo shoe;
  final String reason;   // 匹配理由（情绪价值文案）
  final String makeup;   // 妆容推荐
  final WeatherInfo weather;

  List<ItemInfo> get items => [top, bottom, shoe];
}

/// 首页底部三张统计卡片
class HomeStats {
  const HomeStats({
    required this.wardrobeItems,
    required this.monthOutfits,
    required this.neverWorn,
  });

  final int wardrobeItems; // 衣橱单品
  final int monthOutfits;  // 本月搭配
  final int neverWorn;     // 未穿单品

  factory HomeStats.mock() =>
      const HomeStats(wardrobeItems: 47, monthOutfits: 18, neverWorn: 9);
}

/// 历史页条目（对应 outfit_history）
class HistoryEntry {
  const HistoryEntry({
    required this.date,
    required this.occasionLabel,
    required this.summary,
    required this.emoji,
    this.rating = 5,
  });

  final String date;          // 10月1日
  final String occasionLabel; // 日常通勤
  final String summary;       // 一句话回溯
  final String emoji;
  final int rating;
}
