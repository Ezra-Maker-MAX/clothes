// 第二阶段数据模拟层
//
// 两套可轮换的通勤搭配 + 统计 + 历史，文案严格按
// 「嘴快心细的伴侣」风格撰写。第三阶段由 ApiClient 真实数据替换。
import '../models/models.dart';

abstract final class MockData {
  /// 首页天气（第三阶段换成和风天气实时接口）
  static const WeatherInfo weather = WeatherInfo(
    tempC: 24,
    feelsLike: 25,
    condition: '多云',
    label: '舒适温度',
    city: '上海',
  );

  /// 场景标签（对应 occasion）
  static const String occasionLabel = '日常通勤';

  /// 统计卡片
  static const HomeStats stats = HomeStats(
    wardrobeItems: 47,
    monthOutfits: 18,
    neverWorn: 9,
  );

  /// 套 A：原型同款（波点 + 斜扣牛仔 + 尖头凉鞋）
  static final OutfitRecommendation outfitA = OutfitRecommendation(
    occasion: 'commute',
    occasionLabel: occasionLabel,
    weather: weather,
    top: const ItemInfo(
      id: 'w_a_top',
      name: '白色波点衬衫',
      emoji: '👚',
      categoryLabel: '上衣',
      colorName: '白色',
    ),
    bottom: const ItemInfo(
      id: 'w_a_bottom',
      name: '斜扣浅蓝牛仔裤',
      emoji: '👖',
      categoryLabel: '裤装',
      colorName: '浅蓝',
    ),
    shoe: const ItemInfo(
      id: 'w_a_shoe',
      name: '米色尖头凉鞋',
      emoji: '👡',
      categoryLabel: '鞋子',
      colorName: '米色',
    ),
    reason: '波点 + 斜扣牛仔 + 米色尖头凉鞋，避开昨天穿过的款式，'
        '温柔又有通勤精致度。',
    makeup: '清透底妆 + 豆沙色唇，会议室灯光下不假面',
  );

  /// 套 B：「换一套」轮换备选
  static final OutfitRecommendation outfitB = OutfitRecommendation(
    occasion: 'commute',
    occasionLabel: occasionLabel,
    weather: weather,
    top: const ItemInfo(
      id: 'w_b_top',
      name: '燕麦色针织开衫',
      emoji: '🧶',
      categoryLabel: '上衣',
      colorName: '燕麦色',
    ),
    bottom: const ItemInfo(
      id: 'w_b_bottom',
      name: '白色阔腿西装裤',
      emoji: '👖',
      categoryLabel: '裤装',
      colorName: '白色',
    ),
    shoe: const ItemInfo(
      id: 'w_b_shoe',
      name: '裸色平底穆勒鞋',
      emoji: '👡',
      categoryLabel: '鞋子',
      colorName: '裸色',
    ),
    reason: '这身不显腰，但只要你一走路，它就会出卖你——'
        '阔腿裤摆 + 燕麦针织，松弛感刚好压住 25°C 的体感。',
    makeup: '微醺腮红 + 有色润唇，藏一点慵懒',
  );

  /// 备选池：「换一套」在此轮换（第三阶段读 alt_outfits_json）
  static final List<OutfitRecommendation> rotation = [outfitA, outfitB];

  /// 衣橱页模拟单品（第二阶段展示 15 件代表单品；
  /// 全量 47 件第三阶段分页加载，统计口径见 [stats]）
  static const List<ItemInfo> wardrobe = [
    // 上衣 (4)
    ItemInfo(id: 'w_m_01', name: '白色波点衬衫', emoji: '👚', categoryLabel: '上衣', colorName: '白色'),
    ItemInfo(id: 'w_m_02', name: '燕麦色针织开衫', emoji: '🧶', categoryLabel: '上衣', colorName: '燕麦色'),
    ItemInfo(id: 'w_m_03', name: '雾霾蓝缎面衬衫', emoji: '👔', categoryLabel: '上衣', colorName: '雾霾蓝'),
    ItemInfo(id: 'w_m_04', name: '条纹长袖T', emoji: '🧵', categoryLabel: '上衣', colorName: '条纹'),
    // 裤装 (3)
    ItemInfo(id: 'w_m_05', name: '斜扣浅蓝牛仔裤', emoji: '👖', categoryLabel: '裤装', colorName: '浅蓝'),
    ItemInfo(id: 'w_m_06', name: '白色阔腿西装裤', emoji: '🩳', categoryLabel: '裤装', colorName: '白色'),
    ItemInfo(id: 'w_m_07', name: '米色烟管裤', emoji: '👖', categoryLabel: '裤装', colorName: '米色'),
    // 裙装 (2)
    ItemInfo(id: 'w_m_08', name: '奶黄色吊带连衣裙', emoji: '👗', categoryLabel: '裙装', colorName: '奶黄'),
    ItemInfo(id: 'w_m_09', name: '灰紫色百褶半裙', emoji: '🩰', categoryLabel: '裙装', colorName: '灰紫'),
    // 外套 (1)
    ItemInfo(id: 'w_m_10', name: '燕麦色风衣', emoji: '🧥', categoryLabel: '外套', colorName: '燕麦色'),
    // 鞋子 (3)
    ItemInfo(id: 'w_m_11', name: '米色尖头凉鞋', emoji: '👡', categoryLabel: '鞋子', colorName: '米色'),
    ItemInfo(id: 'w_m_12', name: '裸色平底穆勒鞋', emoji: '👡', categoryLabel: '鞋子', colorName: '裸色'),
    ItemInfo(id: 'w_m_13', name: '白色小皮鞋', emoji: '🥿', categoryLabel: '鞋子', colorName: '白色'),
    // 配饰 (2)
    ItemInfo(id: 'w_m_14', name: '珍珠耳环', emoji: '💠', categoryLabel: '配饰', colorName: '珍珠白'),
    ItemInfo(id: 'w_m_15', name: '米色腋下包', emoji: '👜', categoryLabel: '配饰', colorName: '米色'),
  ];

  /// 搭配页模拟数据：历史搭配拼图卡（多单品组合 + 场合标签 + 日期）
  static const List<(String, String, String, List<String>)> outfitCards = [
    ('通勤', '10月1日', '🧶', ['🧶', '👖', '👜', '👡']),
    ('约会', '9月28日', '🌼', ['👗', '👡', '💠', '👛']),
    ('通勤', '9月26日', '🫧', ['👚', '👖', '👟', '💠']),
    ('休闲', '9月21日', '🍂', ['🧥', '🩳', '🥿', '👜']),
  ];

  /// 历史页模拟数据
  static const List<HistoryEntry> history = [
    HistoryEntry(
      date: '昨天',
      occasionLabel: '日常通勤',
      summary: '条纹针织 + 直筒牛仔裤 + 白色板鞋，稳妥但有点腻，下次少穿。',
      emoji: '🧵',
    ),
    HistoryEntry(
      date: '10月1日',
      occasionLabel: '约会',
      summary: '奶黄色连衣裙 + 编织凉鞋，他多看了两眼，你知道是为什么。',
      emoji: '🌼',
    ),
    HistoryEntry(
      date: '9月28日',
      occasionLabel: '日常通勤',
      summary: '灰紫卫衣 + 米色烟管裤，周二人最丧，穿得舒服最重要。',
      emoji: '🫧',
      rating: 4,
    ),
  ];

  /// 问候语：按当前时段生成情绪价值文案
  static String greeting(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 11) return '早上好，尊贵的公主';
    if (h >= 11 && h < 13) return '中午好，尊贵的公主';
    if (h >= 13 && h < 18) return '下午好，尊贵的公主';
    if (h >= 18 && h < 23) return '晚上好，尊贵的公主';
    return '夜深了，尊贵的公主';
  }

  /// 问候区小字：嘴快心细，不油腻
  static String greetingTip(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 11) return '今天想被夸哪一面？';
    if (h >= 11 && h < 13) return '午后阳光不错，别辜负它';
    if (h >= 13 && h < 18) return '今天想被夸哪一面？';
    if (h >= 18 && h < 23) return '晚风正温柔，适合见想见的人';
    return '先睡，搭配的事明天交给今天的你';
  }
}
