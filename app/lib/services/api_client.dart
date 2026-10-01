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
        .timeout(const Duration(seconds: 10));
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
        .timeout(const Duration(seconds: 10));
    _ensureOk(res);
  }

  /// 历史穿搭：GET /api/history → 真实搭配日记（含单品名）
  static Future<List<HistoryEntry>> getHistory() async {
    if (useMock) return MockData.history;
    final res = await _http
        .get(Uri.parse('$baseUrl/api/history?userId=$demoUserId'))
        .timeout(const Duration(seconds: 10));
    final data = _data(res);
    final items = (data['items'] as List?) ?? [];
    return items.map<HistoryEntry>((raw) {
      final r = raw as Map<String, dynamic>;
      final names = ((r['itemNames'] as List?) ?? []).map((e) => e as String).toList();
      final occasion = _occasionLabel(r['occasion'] as String? ?? 'casual');
      final dateStr = _formatDate(r['worn_date'] as String? ?? '');
      final summary = names.isNotEmpty
          ? '${names.join(' + ')}。'
          : (r['reason'] as String? ?? '今天这一身，记下就好。');
      final rating = (r['rating'] as num?)?.toInt() ?? 5;
      return HistoryEntry(
        date: dateStr, occasionLabel: occasion, summary: summary, emoji: '👗', rating: rating,
      );
    }).toList();
  }

  /// 首页三卡统计：衣橱总数 / 本月搭配 / 未穿单品（真实模式）
  static Future<HomeStats> getStats() async {
    if (useMock) return MockData.stats;
    try {
      final w = await _http
          .get(Uri.parse('$baseUrl/api/wardrobe?userId=$demoUserId'))
          .timeout(const Duration(seconds: 10));
      final wd = _data(w);
      final wItems = (wd['items'] as List?) ?? [];
      final wardrobeItems = wItems.length;
      final neverWorn = wItems.where((i) => i['last_worn_at'] == null).length;
      final h = await _http
          .get(Uri.parse('$baseUrl/api/history?userId=$demoUserId'))
          .timeout(const Duration(seconds: 10));
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

  /// 'YYYY-MM-DD' → '10月2日'
  static String _formatDate(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    return '${parts[1]}月${parts[2]}日';
  }
}
