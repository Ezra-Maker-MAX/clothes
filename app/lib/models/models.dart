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

/// 动态分类（对应 /api/categories；内置行 id = 引擎 key）
class CategoryInfo {
  const CategoryInfo({
    required this.id,
    required this.name,
    required this.engineKey,
    required this.sortOrder,
    this.isBuiltin = false,
  });

  final String id;
  final String name;
  final String engineKey;   // 映射到推荐引擎的适配类别
  final int sortOrder;
  final bool isBuiltin;     // 内置分类不可删除

  /// 引擎适配类别 → 默认 emoji（无图单品卡片用）
  String get emoji => switch (engineKey) {
        'tops' => '👚',
        'bottoms' => '👖',
        'dresses' => '👗',
        'outerwear' => '🧥',
        'shoes' => '👡',
        _ => '👜',
      };
}

/// 单品展示模型（对应 wardrobe_items 行 + 前端展示字段）
class ItemInfo {
  const ItemInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.categoryLabel,
    this.categoryId = '',
    this.imageUrl,
    this.imageUrls = const [],
    this.pinned = false,
    this.colorName,
    this.lastWornAt,
    this.brand,
    this.wearCount = 0,
    this.price,
  });

  final String id;            // 单品唯一 ID（衣橱落库后由后端返回，acceptOutfit 据此写历史）
  final String name;
  final String categoryLabel; // 上衣 / 裤装 / 鞋子（动态分类翻译后的展示名）
  final String categoryId;    // 分类 id（编辑回显/表单提交用；空 = mock 数据）
  final String emoji;         // 分类默认 emoji；有 imageUrl 时卡片优先网络图
  final String? imageUrl;     // 主图 URL（Vercel Blob）
  final List<String> imageUrls; // 多图列表（P0：主图+辅助图；详情页横滑画廊用）
  final bool pinned;          // 置顶（衣橱列表排序优先）
  final String? colorName;
  final String? lastWornAt;   // 最近一次上身穿的日期（null = 还没上过身，衣橱页统计用）
  final String? brand;        // 品牌（手动录入可选填）
  final int wearCount;        // 累计穿着次数（列表/详情展示）
  final double? price;        // 购入价格（元）；单次穿着成本 = price / max(wearCount, 1)

  /// 单次穿着成本文案：未填价格或没穿过 → '—'
  String get costPerWear {
    if (price == null || price! <= 0) return '—';
    if (wearCount <= 0) return '—';
    final v = price! / wearCount;
    return '¥${v.toStringAsFixed(v < 100 ? 1 : 0)}';
  }

  /// 展示图列表：多图优先，回退主图，再回退空（调用方显示 emoji 占位）
  List<String> get gallery {
    if (imageUrls.isNotEmpty) return imageUrls;
    if (imageUrl != null && imageUrl!.startsWith('http')) return [imageUrl!];
    return const [];
  }

  ItemInfo copyWith({bool? pinned, List<String>? imageUrls, String? imageUrl}) {
    return ItemInfo(
      id: id, name: name, emoji: emoji, categoryLabel: categoryLabel,
      categoryId: categoryId, imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls, pinned: pinned ?? this.pinned,
      colorName: colorName, lastWornAt: lastWornAt, brand: brand,
      wearCount: wearCount, price: price,
    );
  }

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
    this.rawDate = '',
    this.itemIds = const [],
    this.source = 'recommended',
    this.rating = 5,
  });

  final String date;          // 10月1日
  final String rawDate;       // 原始 'YYYY-MM-DD'（穿搭日记日历按月点亮，防跨月错亮）
  final String occasionLabel; // 日常通勤
  final String summary;       // 一句话回溯
  final String emoji;
  final List<String> itemIds; // 这一套的单品 id（搭配页拼图卡渲染用）
  final String source;        // recommended = AI 推荐 / manual = DIY 自配
  final int rating;
}
