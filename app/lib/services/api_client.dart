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

  /// 展示用版本号（设置页「关于」）；与 pubspec.yaml 保持一致
  static const String appVersion = '0.2.0';

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

  /// 「DIY 搭配」：自选单品存为一套（source=manual，不推进推荐排重统计以外字段）
  static Future<void> saveManualOutfit(List<ItemInfo> items) async {
    if (useMock) return;
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/history'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': demoUserId,
            'itemIds': items.map((i) => i.id).toList(),
            'occasion': 'casual',
            'source': 'manual',
          }),
        )
        .timeout(_fastTimeout);
    _ensureOk(res);
  }

  /// 历史穿搭：GET /api/history → 真实搭配日记（含单品名）
  /// month: 'YYYY-MM' 只拉该月（穿搭日记按月翻页用；服务端已支持 month 过滤）
  static Future<List<HistoryEntry>> getHistory({String? month}) async {
    if (useMock) return MockData.history;
    final res = await _http
        .get(Uri.parse(
            '$baseUrl/api/history?userId=$demoUserId${month != null ? '&month=$month' : ''}'))
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
        itemIds: ((r['itemIds'] as List?) ?? []).map((e) => e as String).toList(),
        source: r['source'] as String? ?? 'recommended',
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
  // 分类（动态）：GET/POST/PATCH/DELETE /api/categories
  // ---------------------------------------------------------------
  /// 内置兜底（分类接口失败/离线时仍可用，id=引擎 key 与内置行一致）
  static const List<CategoryInfo> builtinCategories = [
    CategoryInfo(id: 'tops', name: '上衣', engineKey: 'tops', sortOrder: 1, isBuiltin: true),
    CategoryInfo(id: 'bottoms', name: '裤装', engineKey: 'bottoms', sortOrder: 2, isBuiltin: true),
    CategoryInfo(id: 'dresses', name: '裙装', engineKey: 'dresses', sortOrder: 3, isBuiltin: true),
    CategoryInfo(id: 'outerwear', name: '外套', engineKey: 'outerwear', sortOrder: 4, isBuiltin: true),
    CategoryInfo(id: 'shoes', name: '鞋子', engineKey: 'shoes', sortOrder: 5, isBuiltin: true),
    CategoryInfo(id: 'bags', name: '包包', engineKey: 'bags', sortOrder: 6, isBuiltin: true),
    CategoryInfo(id: 'accessories', name: '配饰', engineKey: 'accessories', sortOrder: 7, isBuiltin: true),
  ];

  static Future<List<CategoryInfo>> getCategories() async {
    if (useMock) return builtinCategories;
    try {
      final res = await _http
          .get(Uri.parse('$baseUrl/api/categories?userId=$demoUserId'))
          .timeout(_fastTimeout);
      final data = _data(res);
      final items = (data['items'] as List?) ?? [];
      if (items.isEmpty) return builtinCategories;
      return items.map<CategoryInfo>((raw) {
        final r = raw as Map<String, dynamic>;
        return CategoryInfo(
          id: r['id'] as String? ?? '',
          name: r['name'] as String? ?? '',
          engineKey: r['engineKey'] as String? ?? 'tops',
          sortOrder: (r['sortOrder'] as num?)?.toInt() ?? 0,
          isBuiltin: r['isBuiltin'] as bool? ?? false,
        );
      }).toList();
    } catch (_) {
      return builtinCategories; // 拉不到就用内置，衣橱永不白屏
    }
  }

  static Future<void> createCategory({
    required String name,
    required String engineKey,
  }) async {
    if (useMock) return;
    final res = await _http
        .post(Uri.parse('$baseUrl/api/categories'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': demoUserId, 'name': name, 'engineKey': engineKey}))
        .timeout(_fastTimeout);
    _ensureOk(res);
  }

  static Future<void> renameCategory({required String id, required String name}) async {
    if (useMock) return;
    final res = await _http
        .patch(Uri.parse('$baseUrl/api/categories'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id': id, 'name': name}))
        .timeout(_fastTimeout);
    _ensureOk(res);
  }

  static Future<void> reorderCategories(List<String> orderedIds) async {
    if (useMock) return;
    final res = await _http
        .patch(Uri.parse('$baseUrl/api/categories'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': demoUserId, 'order': orderedIds}))
        .timeout(_fastTimeout);
    _ensureOk(res);
  }

  static Future<void> deleteCategory(String id) async {
    if (useMock) return;
    final res = await _http
        .delete(Uri.parse('$baseUrl/api/categories?id=$id&userId=$demoUserId'))
        .timeout(_fastTimeout);
    _ensureOk(res);
  }

  /// 分类 id → 中文名（内置兜底翻译；动态分类传入列表优先）
  static String categoryLabelOf(String categoryId, {List<CategoryInfo>? categories}) {
    final list = categories ?? builtinCategories;
    for (final c in list) {
      if (c.id == categoryId) return c.name;
    }
    return builtinCategories.firstWhere((c) => c.id == categoryId,
            orElse: () => const CategoryInfo(id: '?', name: '配饰', engineKey: 'accessories', sortOrder: 99))
        .name;
  }

  static String categoryEmojiOf(String categoryId, {List<CategoryInfo>? categories}) {
    final list = categories ?? builtinCategories;
    for (final c in list) {
      if (c.id == categoryId) return c.emoji;
    }
    return '👜';
  }

  // ---------------------------------------------------------------
  // 衣橱：GET / POST / PATCH / DELETE /api/wardrobe
  // ---------------------------------------------------------------
  /// 衣橱真实单品列表（lastWornAt 为 null 即「还没上过身」）
  /// categories 不传则自动拉取一次用于翻译动态分类
  static Future<List<ItemInfo>> getWardrobe({List<CategoryInfo>? categories}) async {
    if (useMock) return MockData.wardrobe;
    final cats = categories ?? await getCategories();
    final res = await _http
        .get(Uri.parse('$baseUrl/api/wardrobe?userId=$demoUserId'))
        .timeout(_fastTimeout);
    final data = _data(res);
    final items = (data['items'] as List?) ?? [];
    return items.map<ItemInfo>((raw) {
      final r = raw as Map<String, dynamic>;
      final catId = r['category'] as String? ?? '';
      CategoryInfo cat = builtinCategories.first;
      for (final c in cats) {
        if (c.id == catId) cat = c;
      }
      // 多图：image_urls 为 JSON 数组字符串（服务端存的 TEXT 列）
      List<String> imgs = const [];
      final rawUrls = r['image_urls'];
      if (rawUrls is String && rawUrls.isNotEmpty) {
        try {
          imgs = (jsonDecode(rawUrls) as List).map((e) => e.toString()).toList();
        } catch (_) {}
      } else if (rawUrls is List) {
        imgs = rawUrls.map((e) => e.toString()).toList();
      }
      return ItemInfo(
        id: r['id'] as String? ?? '',
        name: r['name'] as String? ?? '未命名单品',
        emoji: cat.emoji,
        categoryLabel: cat.name,
        categoryId: catId,
        imageUrl: r['image_url'] as String?,
        imageUrls: imgs,
        pinned: (r['pinned'] as num?)?.toInt() == 1,
        colorName: r['color_name'] as String?,
        lastWornAt: r['last_worn_at'] as String?,
        brand: r['brand'] as String?,
        wearCount: (r['wear_count'] as num?)?.toInt() ?? 0,
        price: (r['price'] as num?)?.toDouble(),
      );
    }).toList();
  }

  /// 手动添加单品（图片可选：已上传的 Blob URL；多图存 JSON 列表，主图走 imageUrl）
  static Future<void> addWardrobeItem({
    required String name,
    required String categoryId,
    String? colorName,
    String? brand,
    double? price,
    String? imageUrl,
    List<String> imageUrls = const [],
    bool pinned = false,
  }) async {
    if (useMock) return;
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/wardrobe'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': demoUserId,
            'name': name,
            'imageUrl': imageUrl ?? 'https://placehold.co/400x533?text=YiNian',
            'category': categoryId,
            if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
            'pinned': pinned,
            if (colorName != null && colorName.isNotEmpty) 'colorName': colorName,
            if (brand != null && brand.isNotEmpty) 'brand': brand,
            if (price != null) 'price': price,
            'source': 'manual',
          }),
        )
        .timeout(_fastTimeout);
    _ensureOk(res);
  }

  /// 编辑单品基础字段（PATCH /api/wardrobe）
  static Future<void> updateWardrobeItem({
    required String id,
    String? name,
    String? categoryId,
    String? colorName,
    String? brand,
    double? price,
    String? imageUrl,
    List<String>? imageUrls,
    bool? pinned,
  }) async {
    if (useMock) return;
    final res = await _http
        .patch(
          Uri.parse('$baseUrl/api/wardrobe'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'id': id,
            if (name != null && name.isNotEmpty) 'name': name,
            if (categoryId != null && categoryId.isNotEmpty) 'category': categoryId,
            if (colorName != null) 'colorName': colorName,
            if (brand != null) 'brand': brand,
            if (price != null) 'price': price,
            if (imageUrl != null) 'imageUrl': imageUrl, // 空串 = 清空主图
            if (imageUrls != null) 'imageUrls': imageUrls, // 空列表 = 清空多图
            if (pinned != null) 'pinned': pinned,
          }),
        )
        .timeout(_fastTimeout);
    _ensureOk(res);
  }

  /// 置顶 / 取消置顶（详情页快捷开关）
  static Future<void> togglePin(String id, bool pinned) =>
      updateWardrobeItem(id: id, pinned: pinned);

  /// 删除单品（软删，历史记录不断链）
  static Future<void> deleteWardrobeItem(String id) async {
    if (useMock) return;
    final res = await _http
        .delete(Uri.parse('$baseUrl/api/wardrobe?id=$id'))
        .timeout(_fastTimeout);
    _ensureOk(res);
  }

  /// 订单文本导入（P2 降级方案：淘宝订单商品行粘贴 → 批量建单品）
  /// 返回导入件数；[unknownCategories] 为猜测失败（默认上衣）的名称，提示用户补分类
  static Future<({int imported, List<String> unknownCategories})> importOrderText(
      String text) async {
    if (useMock) throw Exception('演示模式不支持导入，连上正式服务再用');
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/import-order'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'userId': demoUserId, 'text': text}),
        )
        .timeout(_genTimeout); // 批量插入可能稍慢
    _ensureOk(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final data = (body['data'] as Map<String, dynamic>?) ?? const {};
    final items = (data['items'] as List?) ?? const [];
    final unknown = items
        .whereType<Map>()
        .where((m) => m['guessed'] == true)
        .map((m) => (m['name'] ?? '').toString())
        .toList();
    return (imported: (data['imported'] as num?)?.toInt() ?? 0, unknownCategories: unknown);
  }

  /// 上传单品图片（/api/upload，base64 JSON 协议）
  /// 返回 (url, cutoutUrl)：cutoutUrl 为服务端 AI 抠图结果（未配置/失败为 null）
  /// 服务端未开通 Blob 存储时抛 501 异常（文案已含开通指引）
  static Future<({String url, String? cutoutUrl})> uploadImage({
    required List<int> bytes,
    required String filename,
    String contentType = 'image/jpeg',
  }) async {
    if (useMock) throw Exception('演示模式：无需上传图片');
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/upload?userId=$demoUserId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'filename': filename,
            'contentType': contentType,
            'dataBase64': base64Encode(bytes),
          }),
        )
        .timeout(_genTimeout); // 图片较大时上传慢，给足时间
    _ensureOk(res);
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final data = (body['data'] as Map<String, dynamic>?) ?? const {};
    return (
      url: (data['url'] as String?) ?? '',
      cutoutUrl: data['cutoutUrl'] as String?,
    );
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
