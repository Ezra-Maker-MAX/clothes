// 私密身形档案 —— 围度 + 9 部位高清图 + 肤色，全量上云（用户自己的 Turso/Blob）
//
// ── 数据真源 ──
// 云端（/api/private-profile，HMAC token 鉴权）是真源；本地 SharedPreferences
// 只做启动缓存/降级（云端连不上时照常查看编辑，恢复后再同步）。
// 图片本体走 /api/upload 上传到用户自己的 Vercel Blob（private/ 目录）。
//
// ── 试衣还原 ──
// 生成时（私密模式）：
//   1) 各部位肤色描述并入 prompt；
//   2) 有高清图的部位整图随请求发给自部署模型服务（partImages），
//      让模型按部位肤色/身形细节还原，最大化试衣真实感。
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'private_mode_service.dart';

/// 一个身体部位的私密数据：肤色 + 高清参考图（都在用户自己的私有 Blob）
///
/// 🔒 [imagePath] 存的是 Blob **pathname**，不是 URL。
///    私密图在 access=private 的 store 里，直链匿名 403 —— 所以拿不到可直连的
///    URL，也**不应该**存 URL（极易被误当成公开地址泄漏）。展示统一走
///    [ApiClient.privateImageUri] 鉴权代理。
class PrivatePart {
  final String skin; // 肤色档位 key（PrivateBodyStore.skinTones 里的 key）
  final String imagePath; // 高清部位图（Blob pathname，空串=未传）

  const PrivatePart({this.skin = '', this.imagePath = ''});

  bool get hasData => skin.isNotEmpty || imagePath.isNotEmpty;

  Map<String, dynamic> toJson() => {'skin': skin, 'imagePath': imagePath};

  static PrivatePart fromJson(dynamic raw) {
    if (raw is Map) {
      // 兼容旧结构：此前误存过 imageUrl（公开 blob 直链），读出来但不再使用，
      // 让用户重新上传一次即可迁移干净，避免继续用公开 URL 展示私密部位图
      return PrivatePart(
        skin: raw['skin'] as String? ?? '',
        imagePath: raw['imagePath'] as String? ?? '',
      );
    }
    return const PrivatePart();
  }
}

class PrivateBodyStore {
  PrivateBodyStore._();

  static const String _cacheKey = 'private_body_v2';

  // ---- 9 个部位（key → 中文 / 发给模型的英文描述） ----
  static const Map<String, (String, String)> parts = {
    'head': ('头/脸', 'head and face'),
    'chest': ('胸', 'chest and bust'),
    'waist': ('腰腹', 'waist and abdomen'),
    'arm': ('手臂', 'arms'),
    'hand': ('手', 'hands'),
    'hip': ('臀', 'hips and buttocks'),
    'thigh': ('大腿', 'thighs'),
    'calf': ('小腿', 'calves'),
    'foot': ('足', 'feet'),
  };

  // ---- 肤色色板（key → 中文 / 色值 / 发给模型的英文描述） ----
  static const List<(String, String, String, String)> skinTones = [
    ('porcelain', '白瓷', '#F6E3D5', 'porcelain fair skin'),
    ('fair', '白皙', '#F0D6C0', 'fair skin'),
    ('warmLight', '浅暖', '#EBCCA8', 'warm light beige skin'),
    ('natural', '自然', '#DFAF86', 'natural medium skin'),
    ('wheat', '小麦', '#C89468', 'wheatish tan skin'),
    ('bronze', '古铜', '#A96F44', 'bronzed tan skin'),
    ('honey', '深蜜', '#8A5430', 'deep honey brown skin'),
    ('deep', '深棕', '#5F3A22', 'deep brown skin'),
  ];

  static String skinLabel(String key) => skinTones
      .firstWhere((t) => t.$1 == key, orElse: () => ('', '', '', ''))
      .$2;

  static String skinHex(String key) => skinTones
      .firstWhere((t) => t.$1 == key, orElse: () => ('', '', '', ''))
      .$3;

  static String skinEn(String key) => skinTones
      .firstWhere((t) => t.$1 == key, orElse: () => ('', '', '', ''))
      .$4;

  /// 肤色 key → int 颜色值（UI 色块用；无效 key 返回灰）
  static int skinColorValue(String key) {
    final hex = skinHex(key).replaceFirst('#', '');
    if (hex.length != 6) return 0xFF9E9E9E;
    return 0xFF000000 | int.parse(hex, radix: 16);
  }

  // ---- 围度（补充试衣间基础数据） ----
  static const Map<String, String> measureLabels = {
    'underbust': '下胸围 cm',
    'thighCm': '大腿围 cm',
    'calfCm': '小腿围 cm',
    'shoulderCm': '肩宽 cm',
  };

  // ---- 内存态（真源的缓存，UI 直接读） ----
  static Map<String, double> _measures = {};
  static Map<String, PrivatePart> _parts = {};
  static List<String> _photos = [];
  static bool _cloudOk = false; // 最近一次同步是否成功（UI 提示用）

  static Map<String, double> get measures => _measures;
  static Map<String, PrivatePart> get partsData => _parts;
  static List<String> get photos => List.unmodifiable(_photos);
  static bool get cloudOk => _cloudOk;
  static double? measure(String field) => _measures[field];

  /// 某部位有没有任何数据（肤色/图）
  static bool partHasData(String key) => (_parts[key] ?? const PrivatePart()).hasData;

  /// 有高清图的部位数（UI 统计用）
  static int get partsWithImage =>
      _parts.values.where((p) => p.imagePath.isNotEmpty).length;

  /// App 启动：先吃本地缓存（秒开），再静默拉云端刷新
  static Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        _applyJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    await syncFromCloud();
  }

  /// 云端 → 内存 → 本地缓存。失败保持现有内存不动（降级可用）
  static Future<bool> syncFromCloud() async {
    final token = PrivateModeService.token;
    if (token == null || token.isEmpty) {
      _cloudOk = false;
      return false;
    }
    final r = await ApiClient.loadPrivateProfile(token);
    if (r == null) {
      _cloudOk = false;
      return false;
    }
    _applyJson({
      'measures': r.body['measures'] ?? const {},
      'parts': r.body['parts'] ?? const {},
      'photos': r.photos,
    });
    _cloudOk = true;
    await _persistLocal();
    return true;
  }
  static void _applyJson(Map<String, dynamic> j) {
    try {
      final m = (j['measures'] as Map?) ?? const {};
      _measures = m.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
      final p = (j['parts'] as Map?) ?? const {};
      _parts = p.map((k, v) => MapEntry(k as String, PrivatePart.fromJson(v)));
      _photos = ((j['photos'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {}
  }

  /// 当前内存态 → 服务端 body JSON
  static Map<String, dynamic> _toBodyJson() => {
        'measures': _measures,
        'parts': _parts.map((k, v) => MapEntry(k, v.toJson())),
      };

  static Future<void> _persistLocal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_cacheKey, jsonEncode({
        'measures': _measures,
        'parts': _parts.map((k, v) => MapEntry(k, v.toJson())),
        'photos': _photos,
      }));
    } catch (_) {}
  }

  /// 云端全量覆盖（内存已是最新，直接推）。失败返回提示（调用方 toast）
  static Future<String?> _push() async {
    final token = PrivateModeService.token;
    if (token == null || token.isEmpty) return '云端会话无效，重新输密码解锁后再同步';
    final err = await ApiClient.savePrivateProfile(
        token, _toBodyJson(), _photos);
    if (err == null) {
      _cloudOk = true;
      await _persistLocal();
    }
    return err;
  }

  // ---- 写操作：先改内存 → 本地缓存 → 云端推送 ----

  /// 保存围度（null/<=0 视为清除该字段）
  static Future<String?> saveMeasures(Map<String, double?> data) async {
    final next = <String, double>{..._measures};
    data.forEach((k, v) {
      if (v == null || v <= 0) {
        next.remove(k);
      } else {
        next[k] = v;
      }
    });
    _measures = next;
    await _persistLocal();
    return _push();
  }

  /// 更新部位肤色
  static Future<String?> savePartSkin(String partKey, String skinKey) async {
    final cur = _parts[partKey] ?? const PrivatePart();
    _parts = {..._parts, partKey: PrivatePart(skin: skinKey, imagePath: cur.imagePath)};
    await _persistLocal();
    return _push();
  }

  /// 上传部位高清图 → 私有 Blob → 记录 pathname
  /// 返回 null=成功；非 null=失败提示
  static Future<String?> uploadPartImage(String partKey, List<int> bytes) async {
    final path = await _upload(bytes);
    if (path == null) return '上传失败：私密图库未配置或网络异常';
    final cur = _parts[partKey] ?? const PrivatePart();
    _parts = {..._parts, partKey: PrivatePart(skin: cur.skin, imagePath: path)};
    await _persistLocal();
    return _push();
  }

  /// 添加私密相册照片
  static Future<String?> addPhoto(List<int> bytes) async {
    final path = await _upload(bytes);
    if (path == null) return '上传失败：私密图库未配置或网络异常';
    _photos = [path, ..._photos];
    await _persistLocal();
    return _push();
  }

  /// 从相册列表移除（Blob 对象保留，不删文件——省一次 API 调用；
  /// 保留的意义是误删可恢复，且 pathname 本身不可猜测）
  static Future<String?> removePhoto(String path) async {
    _photos = _photos.where((u) => u != path).toList();
    await _persistLocal();
    return _push();
  }

  /// 上传到私密 store，返回 pathname（失败返回 null）
  ///
  /// 私密上传必须带会话令牌：服务端要验token，否则任何人 POST 都能往私库塞图。
  static Future<String?> _upload(List<int> bytes) async {
    final token = PrivateModeService.token;
    if (token == null || token.isEmpty) return null;
    try {
      final r = await ApiClient.uploadImage(
        bytes: bytes,
        filename: 'pv_${DateTime.now().millisecondsSinceEpoch}.jpg',
        folder: 'private',
        privateToken: token,
      );
      // 私密分支服务端不回 url，只回 pathname
      final p = r.pathname;
      return p.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }

  // ---- 试衣生成辅助 ----

  /// 各部位肤色英文描述（发给模型并入 prompt），如
  /// "porcelain fair skin on head and face, natural medium skin on arms"
  /// 只取有肤色记录的部位；没有任何记录返回空串
  static String get skinPromptFragment {
    final frags = <String>[];
    parts.forEach((key, value) {
      final (_, en) = value;
      final p = _parts[key];
      if (p != null && p.skin.isNotEmpty) {
        final en2 = skinEn(p.skin);
        if (en2.isNotEmpty) frags.add('$en2 on $en');
      }
    });
    return frags.join(', ');
  }

  /// 有高清图的部位 → key（供生成前下载图片用）
  static List<String> get partsWithImageKeys => parts.keys
      .where((k) => (_parts[k]?.imagePath ?? '').isNotEmpty)
      .toList();

  static String? partImagePath(String key) {
    final p = _parts[key]?.imagePath ?? '';
    return p.isEmpty ? null : p;
  }

  /// 部位图 / 相册图的鉴权取图地址（给 Image.network 用）
  ///
  /// 返回 null 表示没图或没解锁（无token 时不该发起请求，否则必 401）。
  static Uri? imageUri(String path) {
    final token = PrivateModeService.token;
    if (path.isEmpty || token == null || token.isEmpty) return null;
    return ApiClient.privateImageUri(path, token);
  }

  /// Image.network 需要的鉴权请求头
  static Map<String, String> get imageHeaders {
    final token = PrivateModeService.token ?? '';
    return ApiClient.privateImageHeaders(token);
  }
}
