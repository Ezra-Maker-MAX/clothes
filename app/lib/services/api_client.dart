// API 客户端 —— 与 Vercel Serverless Functions 通信的唯一入口
//
// 第二阶段（数据模拟）：useMock = true，全部走 MockData。
// 第三阶段（联调）：构建时 --dart-define=USE_MOCK=false 切真实 API；
//   环境变量 API_BASE_URL 指定后端地址（本地联调默认 http://localhost:3001）。
//
// ⚠️ 数据库凭证（TURSO_URL / TURSO_AUTH_TOKEN）只存在于 Vercel 函数侧，
//    客户端永远只走 HTTPS 调 API，绝不落库凭证。
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'mock_data.dart';

class ApiClient {
  ApiClient._();

  /// 第三阶段通过 --dart-define=USE_MOCK=false 关闭模拟；默认保持 true（稳妥）
  static const bool useMock = bool.fromEnvironment('USE_MOCK', defaultValue: true);

  /// --dart-define=API_BASE_URL=... 注入后端地址（本地联调 / Vercel 域名）
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3001',
  );

  static const String demoUserId = 'u_demo_0001';

  /// 超时分档：
  /// - 简单查询（历史/衣橱/统计/写历史）15s，正常 1s 内返回；
  /// - 推荐生成 30s —— 「换一套」(refresh=1) 走完整链路（天气+排重引擎+LLM 润色，
  ///   reasoning 模型本身就要 10~20s），10s 必超时；30s 与服务端 maxDuration 对齐。
  static const Duration _fastTimeout = Duration(seconds: 15);
  static const Duration _genTimeout = Duration(seconds: 30);

  static final http.Client _http = http.Client();

  /// 统一拆包 { ok, data } 并校验状态码
  static Map<String, dynamic> _data(http.Response res) {
    _ensureOk(res);
    return (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------
  // 今日推荐：GET /api/recommend?userId=&occasion=&tempC=[&refresh=1]
  // ---------------------------------------------------------------
  static Future<OutfitRecommendation> getRecommendation({
    String occasion = 'commute',
    bool refresh = false,
    int tempC = 24,
  }) async {
    if (useMock) {
      // 模拟「换一套」轮换 + 网络延迟，让交互手感真实
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final pool = MockData.rotation;
      _mockCursor = (_mockCursor + (refresh ? 1 : 0)) % pool.length;
      return pool[_mockCursor];
    }
    final res = await _http
        .get(Uri.parse(
          '$baseUrl/api/recommend?userId=$demoUserId&occasion=$occasion'
          '${refresh ? '&refresh=1' : ''}&tempC=$tempC',
        ))
        .timeout(_genTimeout);
    final body = _data(res);
    final w = (body['weather'] as Map<String, dynamic>?) ?? {};
    return OutfitRecommendation(
      occasion: body['occasion'] as String? ?? occasion,
      occasionLabel: _occasionLabel(body['occasion'] as String? ?? occasion),
      weather: WeatherInfo(
        tempC: (w['tempC'] as num?)?.toInt() ?? 24,
        feelsLike: (w['feelsLike'] as num?)?.toInt() ?? 25,
        condition: w['condition'] as String? ?? '多云',
        label: _tempLabel((w['feelsLike'] as num?)?.toInt() ?? 25),
        city: w['city'] as String? ?? '本地',
      ),
      top: _item((body['items'] as Map)['top'] as Map<String, dynamic>, '上衣', '👚'),
      bottom: _item((body['items'] as Map)['bottom'] as Map<String, dynamic>, '裤装', '👖'),
      shoe: _item((body['items'] as Map)['shoe'] as Map<String, dynamic>, '鞋子', '👡'),
      reason: body['reason'] as String? ?? '',
      makeup: body['makeup'] as String? ?? '',
    );
  }

  /// 「就穿这套」：POST /api/history（写历史 + 更新排重字段）
  static Future<void> acceptOutfit(OutfitRecommendation outfit) async {
    if (useMock) return; // 第二阶段仅本地确认，第三阶段落库
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/history'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': demoUserId,
            'itemIds': [outfit.top.id, outfit.bottom.id, outfit.shoe.id],
            'occasion': outfit.occasion,
            'weatherSnapshot': {
              'tempC': outfit.weather.tempC,
              'feelsLike': outfit.weather.feelsLike,
              'condition': outfit.weather.condition,
              'city': outfit.weather.city,
            },
          }),
        )
        .timeout(_fastTimeout);
    _ensureOk(res);
  }

  /// 历史穿搭：GET /api/history → 真实搭配日记（含单品名）
  static Future<List<HistoryEntry>> getHistory() async {
    if (useMock) return MockData.history;
    final res = await _http
        .get(Uri.parse('$baseUrl/api/history?userId=$demoUserId'))
        .timeout(_fastTimeout);
    final data = _data(res);
    final items = (data['items'] as List?) ?? [];
    final entries = items.map<HistoryEntry>((raw) {
      final r = raw as Map<String, dynamic>;
      final occasionKey = r['occasion'] as String? ?? 'casual';
      final names = ((r['itemNames'] as List?) ?? []).map((e) => e as String).toList();
      final dateStr = _formatDate(r['worn_date'] as String? ?? '');
      final summary = names.isNotEmpty
          ? '${names.join(' + ')}。'
          : (r['reason'] as String? ?? '今天这一身，记下就好。');
      final rating = (r['rating'] as num?)?.toInt() ?? 5;
      return HistoryEntry(
        date: dateStr,
        rawDate: r['worn_date'] as String? ?? '',
        occasionLabel: _occasionLabel(occasionKey),
        summary: summary,
        emoji: switch (occasionKey) {
          'commute' => '👔',
          'date' => '💄',
          'interview' => '💼',
          'party' => '🥂',
          _ => '🌿',
        },
        rating: rating,
      );
    }).toList();
    // 时间线统一按日期倒序（新→旧），不依赖服务端排序；无日期的沉底
    entries.sort((a, b) => b.rawDate.compareTo(a.rawDate));
    return entries;
  }

  /// 首页三卡统计：衣橱总数 / 本月搭配 / 未穿单品（真实模式）
  static Future<HomeStats> getStats() async {
    if (useMock) return MockData.stats;
    try {
      final w = await _http
          .get(Uri.parse('$baseUrl/api/wardrobe?userId=$demoUserId'))
          .timeout(_fastTimeout);
      final wd = _data(w);
      final wItems = (wd['items'] as List?) ?? [];
      final wardrobeItems = wItems.length;
      final neverWorn = wItems.where((i) => i['last_worn_at'] == null).length;
      final h = await _http
          .get(Uri.parse('$baseUrl/api/history?userId=$demoUserId'))
          .timeout(_fastTimeout);
      final hd = _data(h);
      final monthOutfits = (hd['monthStats']?['thisMonth'] as num?)?.toInt() ?? 0;
      return HomeStats(
        wardrobeItems: wardrobeItems, monthOutfits: monthOutfits, neverWorn: neverWorn,
      );
    } catch (_) {
      return MockData.stats; // 统计失败不影响主流程，回退展示
    }
  }

  // ---------------------------------------------------------------
  // 衣橱：GET / POST /api/wardrobe
  // ---------------------------------------------------------------
  /// 服务端分类 key（types.ts）↔ 客户端中文标签
  static String _categoryKey(String label) => switch (label) {
        '上衣' => 'tops',
        '裤装' => 'bottoms',
        '裙装' => 'dresses',
        '外套' => 'outerwear',
        '鞋子' => 'shoes',
        _ => 'accessories', // 配饰（服务端 bags 归并展示）
      };

  static String _categoryLabel(String key) => switch (key) {
        'tops' => '上衣',
        'bottoms' => '裤装',
        'dresses' => '裙装',
        'outerwear' => '外套',
        'shoes' => '鞋子',
        _ => '配饰', // bags / accessories
      };

  static String _categoryEmoji(String label) => switch (label) {
        '上衣' => '👚',
        '裤装' => '👖',
        '裙装' => '👗',
        '外套' => '🧥',
        '鞋子' => '👡',
        _ => '👜',
      };

  /// 衣橱真实单品列表（lastWornAt 为 null 即「还没上过身」）
  static Future<List<ItemInfo>> getWardrobe() async {
    if (useMock) return MockData.wardrobe;
    final res = await _http
        .get(Uri.parse('$baseUrl/api/wardrobe?userId=$demoUserId'))
        .timeout(_fastTimeout);
    final data = _data(res);
    final items = (data['items'] as List?) ?? [];
    return items.map<ItemInfo>((raw) {
      final r = raw as Map<String, dynamic>;
      final label = _categoryLabel(r['category'] as String? ?? '');
      return ItemInfo(
        id: r['id'] as String? ?? '',
        name: r['name'] as String? ?? '未命名单品',
        emoji: _categoryEmoji(label),
        categoryLabel: label,
        imageUrl: r['image_url'] as String?,
        colorName: r['color_name'] as String?,
        lastWornAt: r['last_worn_at'] as String?,
      );
    }).toList();
  }

  /// 手动添加单品（拍照/抠图上传属后续阶段，图片先落占位图满足服务端必填）
  static Future<void> addWardrobeItem({
    required String name,
    required String categoryLabel,
    String? colorName,
  }) async {
    if (useMock) return;
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/wardrobe'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': demoUserId,
            'name': name,
            'imageUrl': 'https://placehold.co/400x533?text=YiNian',
            'category': _categoryKey(categoryLabel),
            if (colorName != null && colorName.isNotEmpty) 'colorName': colorName,
            'source': 'manual',
          }),
        )
        .timeout(_fastTimeout);
    _ensureOk(res);
  }

  // ---------------------------------------------------------------
  // 工具
  // ---------------------------------------------------------------
  static int _mockCursor = 0;

  static void _ensureOk(http.Response res) {
    if (res.statusCode != 200) {
      throw Exception('API ${res.statusCode}: ${res.body}');
    }
  }

  static ItemInfo _item(Map<String, dynamic> raw, String category, String emoji) {
    return ItemInfo(
      id: raw['id'] as String? ?? '',
      name: raw['name'] as String? ?? '',
      emoji: emoji,
      categoryLabel: category,
      imageUrl: raw['image_url'] as String?,
      colorName: raw['color_name'] as String?,
    );
  }

  static String _occasionLabel(String key) => switch (key) {
        'commute' => '日常通勤',
        'date' => '约会',
        'interview' => '面试',
        'party' => '聚会',
        _ => '休闲日常',
      };

  /// 体感温度 → 暖色标签文案（对应 WeatherCard 的强调色标签）
  static String _tempLabel(int feels) =>
      feels >= 28 ? '偏热注意' : feels >= 18 ? '舒适温度' : '微凉保暖';

  /// 日期健壮化：'YYYY-MM-DD' / 'YYYY-MM-DD HH:MM:SS' / ISO 'T' 格式 → '10月2日'
  /// （截掉时间部分、去前导零；格式不认识就原样返回，不让 UI 出现乱码日期）
  static String _formatDate(String iso) {
    final dayPart = iso.split(RegExp(r'[T ]')).first;
    final parts = dayPart.split('-');
    if (parts.length != 3) return iso;
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (m == null || d == null) return dayPart;
    return '$m月$d日';
  }
}
