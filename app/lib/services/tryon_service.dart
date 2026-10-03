// 虚拟试衣 · 自部署模型适配层（实验性）
//
// 定位（架构级隐私隔离，重要）：
// - 模型服务由用户自行部署并维护（本地电脑 / 局域网 / 自有服务器），App 只做「直连客户端」；
// - 试衣相关的图片与参数只从手机直发到用户配置的服务地址，
//   不经过衣念的 Vercel 服务端，不写入 Turso / Vercel Blob —— 云端零留存；
// - 服务地址等配置仅保存在手机本地（SharedPreferences），不上传。
//
// 协议约定（完整说明与适配层示例见 docs/tryon-api.md）：
//   连接测试：GET  {baseUrl}/health                       → 任意 2xx 即在线
//   生成试穿：POST {baseUrl}{path}（默认 /tryon）
//     body: {
//       "personImages": ["<base64>", ...],   // 1~5 张人像
//       "garmentImage": "<base64>",          // 服装平铺图
//       "poseImage": "<base64>" | null,      // 可选：姿势参考
//       "body": { heightCm?, weightKg?, bust?, waist?, hips? },  // 可选身体数据
//       "prompt": "..." | null,              // 可选补充描述
//       "options": { ... }                   // 自定义透传（留给模型侧自由扩展）
//     }
//   响应三选一（自动兼容）：
//     a) {"image": "<base64>"}
//     b) {"imageUrl": "https://..."}          // 服务自己出图链接
//     c) 响应体直接是图片二进制（Content-Type: image/*）
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'model_hub_service.dart';

/// 用户在设置里维护的试衣服务配置（仅存本地）
///
/// 2026-10 起：baseUrl / apiKey / 模型选择统一由 ModelHubService 管理（设置页「自部署模型」区），
/// 本类只保留**协议细节**（路径与鉴权头），并额外携带选中的图像模型名传给后端。
class TryonConfig {
  const TryonConfig({
    this.enabled = false,
    this.baseUrl = '',
    this.path = '/tryon',
    this.apiKey = '',
    this.model = '',
  });

  final bool enabled;
  final String baseUrl; // 如 http://192.168.1.5:8000
  final String path; // 生成接口路径，默认 /tryon
  final String apiKey; // 可选，将以 X-API-Key 头发送
  final String model; // 选中的图像模型名，空 = 由后端自己决定

  /// 规范化 baseUrl：去尾斜杠 + 校验 http/https + host 非空
  static String? normalizeBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.startsWith('http://') && !s.startsWith('https://')) return null;
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return Uri.tryParse(s)?.host.isEmpty == false ? s : null;
  }

  bool get isReady =>
      enabled && normalizeBase(baseUrl) != null && path.trim().isNotEmpty;

  Uri? healthUri() {
    final base = normalizeBase(baseUrl);
    return base == null ? null : Uri.parse('$base/health');
  }

  Uri? generateUri() {
    final base = normalizeBase(baseUrl);
    if (base == null) return null;
    // 走 OpenAI 兼容图像接口时，base 后通常已含 /v1，这里直接补 /images/generations
    if (path.trim().isEmpty) {
      return Uri.tryParse(base.endsWith('/v1')
          ? '$base/images/generations'
          : '$base/v1/images/generations');
    }
    final p = path.trim();
    if (!p.startsWith('/')) return null;
    return Uri.parse('$base$p');
  }

  /// 是否走 OpenAI 兼容协议（决定请求体格式与鉴权头）
  bool get openAiCompat => path.trim().isEmpty;
}

/// 可选身体数据（cm / kg），全可空，用户愿填才随请求发送
/// heightCm~hips 五项来自试衣间表单；underbust 等四项来自私密空间（解锁后才合并进来）
class TryonBodyData {
  const TryonBodyData({
    this.heightCm,
    this.weightKg,
    this.bust,
    this.waist,
    this.hips,
    this.underbust,
    this.thighCm,
    this.calfCm,
    this.shoulderCm,
  });

  final double? heightCm;
  final double? weightKg;
  final double? bust;
  final double? waist;
  final double? hips;
  final double? underbust;  // 下胸围
  final double? thighCm;    // 大腿围
  final double? calfCm;     // 小腿围
  final double? shoulderCm; // 肩宽

  Map<String, double?> toJson() => {
        'heightCm': heightCm,
        'weightKg': weightKg,
        'bust': bust,
        'waist': waist,
        'hips': hips,
        'underbust': underbust,
        'thighCm': thighCm,
        'calfCm': calfCm,
        'shoulderCm': shoulderCm,
      };
}

class TryonService {
  TryonService();

  // SharedPreferences keys
  //注意：baseUrl / apiKey / model 现在由 ModelHubService（mh_*）管理，
  // 这里仅保留旧键用于**首次迁移**（把老配置搬进模型中心），之后不再写。
  static const _kEnabled = 'tryon_enabled';
  static const _kBase = 'tryon_base_url';
  static const _kPath = 'tryon_path';
  static const _kKey = 'tryon_api_key';

  /// 生成接口超时：本地模型出图慢（30s~3min 常见），给足余量
  static const Duration _genTimeout = Duration(seconds: 180);
  static const Duration _pingTimeout = Duration(seconds: 10);

  /// 由模型中心配置派生试衣配置（单一数据源，避免两处设置打架）
  static TryonConfig fromHub(ModelHubConfig hub) => TryonConfig(
        enabled: hub.enabled,
        baseUrl: hub.baseUrl,
        path: hub.tryonPath,
        apiKey: hub.apiKey,
        model: hub.imageModel,
      );

  /// 读试衣配置：优先从模型中心取；模型中心为空时回退到旧键并顺手迁移一次，
  /// 免得老用户升级后要重新填一遍地址。
  static Future<TryonConfig> loadConfig() async {
    final hub = await ModelHubService.loadConfig();
    if (hub.baseUrl.isNotEmpty || hub.enabled) return fromHub(hub);

    final sp = await SharedPreferences.getInstance();
    final legacyBase = sp.getString(_kBase) ?? '';
    if (legacyBase.isEmpty) return fromHub(hub);

    final migrated = hub.copyWith(
      baseUrl: legacyBase,
      apiKey: sp.getString(_kKey) ?? '',
      tryonPath: sp.getString(_kPath) ?? '/tryon',
      enabled: sp.getBool(_kEnabled) ?? false,
    );
    await ModelHubService.saveConfig(migrated);
    return fromHub(migrated);
  }

  static Future<void> saveConfig(TryonConfig c) async {
    // 写进模型中心，不再写tryon_*（保持单一数据源）
    final hub = await ModelHubService.loadConfig();
    await ModelHubService.saveConfig(hub.copyWith(
      enabled: c.enabled,
      baseUrl: c.baseUrl.trim(),
      tryonPath: c.path.trim().isEmpty ? '/tryon' : c.path.trim(),
      apiKey: c.apiKey.trim(),
      imageModel: c.model.trim().isEmpty ? hub.imageModel : c.model.trim(),
    ));
  }

  Map<String, String> _headers(TryonConfig c) => {
        'Content-Type': 'application/json',
        if (c.apiKey.isNotEmpty) 'X-API-Key': c.apiKey,
        if (c.apiKey.isNotEmpty) 'Authorization': 'Bearer ${c.apiKey}',
      };

  /// 连接测试：GET {baseUrl}/health，任意 2xx 即在线
  /// 返回 null 表示成功（在线），否则返回给用户的错误文案
  Future<String?> testConnection({required String baseUrl, String apiKey = ''}) async {
    final base = TryonConfig.normalizeBase(baseUrl);
    if (base == null) return '服务地址不合法，要以 http:// 或 https:// 开头';
    final c = TryonConfig(enabled: true, baseUrl: base, apiKey: apiKey);
    final uri = c.healthUri()!;
    try {
      final r = await http.get(uri, headers: _headers(c)).timeout(_pingTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) return null;
      return '服务在线但返回了 ${r.statusCode}，检查 /health 是否存在';
    } on TimeoutException {
      return '连不上（10s 超时）。确认手机与服务在同一网络、地址端口正确、防火墙已放行';
    } catch (e) {
      return '连接失败：${_short(e)}';
    }
  }

  /// 生成试穿图。成功返回图片字节；失败抛异常（文案已人话化）
  ///
  /// 两套协议自动分派：
  ///   - 自研（path 非空，默认 /tryon）：见 docs/tryon-api.md，body 传 personImages/garmentImage
  ///   - OpenAI 兼容（path 清空）：POST /v1/images/generations，body 走标准格式
  ///     （image = [人像…] + [服装]，model 取设置里选的图像模型）
  /// [partImages] 身体部位细节参考图（私密模式：头/胸/腰/…→高清图），
  ///   随请求发给自部署服务，模型按部位肤色/细节还原，提升真实感。
  Future<Uint8List> generate({
    required TryonConfig c,
    required List<Uint8List> personImages,
    required Uint8List garmentImage,
    Uint8List? poseImage,
    TryonBodyData? body,
    String? prompt,
    Map<String, Object?>? options,
    Map<String, Uint8List>? partImages,
  }) async {
    final uri = c.generateUri();
    if (uri == null) throw Exception('试衣服务未配置好：去设置里检查服务地址与接口路径');
    if (personImages.isEmpty) throw Exception('至少要一张人像照');
    if (personImages.length > 5) throw Exception('人像最多 5 张');

    final Map<String, Object?> payload = c.openAiCompat
        ? _openAiPayload(c, personImages, garmentImage, prompt, partImages)
        : _customPayload(
            personImages, garmentImage, poseImage, body, prompt, options, partImages);

    final http.Response r;
    try {
      r = await http
          .post(uri, headers: _headers(c), body: jsonEncode(payload))
          .timeout(_genTimeout);
    } on TimeoutException {
      throw Exception('等了 3 分钟还没出图。本地模型可能太慢或卡住了，去服务端日志看看');
    } catch (e) {
      throw Exception('请求发不出去：${_short(e)}。确认服务还在运行、手机网络没变');
    }

    // 兼容 c)：响应体直接是图片二进制
    final ct = (r.headers['content-type'] ?? '').toLowerCase();
    if (ct.startsWith('image/')) {
      if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
      throw Exception('服务返回 ${r.statusCode}，看看服务端日志');
    }

    Map<String, dynamic>? json;
    try {
      json = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {/* 不是 JSON，走下面的错误分支 */}

    if (r.statusCode < 200 || r.statusCode >= 300) {
      final detail = _errDetail(json);
      throw Exception('服务返回 ${r.statusCode}${detail == '' ? '' : '：$detail'}');
    }
    if (json == null) throw Exception('服务返回了看不懂的内容（非 JSON 也非图片）');

    // OpenAI 兼容：{"data":[{"b64_json":"…"}] 或 {"data":[{"url":"…"}]}]}
    if (json['data'] is List && (json['data'] as List).isNotEmpty) {
      final first = (json['data'] as List).first;
      if (first is Map) {
        final b64 = first['b64_json'];
        if (b64 is String && b64.isNotEmpty) {
          return base64Decode(b64.startsWith('data:') ? b64.split(',').last : b64);
        }
        final u = first['url'];
        if (u is String && u.isNotEmpty) {
          return _download(u, c);
        }
      }
    }

    // 兼容 a)：{"image": "<base64>"}
    final img = json['image'];
    if (img is String && img.isNotEmpty) {
      return base64Decode(img.startsWith('data:') ? img.split(',').last : img);
    }
    // 兼容 b)：{"imageUrl": "..."}
    final url = json['imageUrl'] ?? json['image_url'];
    if (url is String && url.isNotEmpty) return _download(url, c);

    final err = json['error'] ?? json['message'];
    throw Exception(err is String && err.isNotEmpty ? err : '服务没返回图片字段');
  }

  /// OpenAI 兼容图像接口的请求体：标准只认 model + prompt + n + size，
  /// 我们的多图输入按各家通行做法放进 prompt 前缀（同时保留 custom 字段，方便自建服务读取）。
  Map<String, Object?> _openAiPayload(
    TryonConfig c,
    List<Uint8List> personImages,
    Uint8List garmentImage,
    String? prompt, [
    Map<String, Uint8List>? partImages,
  ]) {
    final buf = StringBuffer();
    for (final p in personImages) {
      buf.writeln('data:image/jpeg;base64,${base64Encode(p)}');
    }
    buf.write('data:image/jpeg;base64,${base64Encode(garmentImage)}');
    return {
      if (c.model.isNotEmpty) 'model': c.model,
      'prompt': prompt == null || prompt.isEmpty
          ? '把第一张人像身上的衣服换成最后一张服装图，保留人脸、发型与背景自然光影'
          : prompt,
      'n': 1,
      'size': '1024x1024',
      // 非标准字段：多数兼容网关会透传，自建服务可直接取用完整多图输入
      'custom': {
        'personImages': personImages.map(base64Encode).toList(),
        'garmentImage': base64Encode(garmentImage),
        if (partImages != null && partImages.isNotEmpty)
          'partImages': partImages.map((k, v) => MapEntry(k, base64Encode(v))),
      },
    };
  }

  /// 自研协议的请求体（docs/tryon-api.md）
  Map<String, Object?> _customPayload(
    List<Uint8List> personImages,
    Uint8List garmentImage,
    Uint8List? poseImage,
    TryonBodyData? body,
    String? prompt,
    Map<String, Object?>? options, [
    Map<String, Uint8List>? partImages,
  ]) =>
      {
        'personImages': personImages.map(base64Encode).toList(),
        'garmentImage': base64Encode(garmentImage),
        'poseImage': poseImage == null ? null : base64Encode(poseImage),
        'body': body?.toJson(),
        'prompt': prompt,
        'options': options,
        if (partImages != null && partImages.isNotEmpty)
          'partImages':
              partImages.map((k, v) => MapEntry(k, base64Encode(v))),
      };

  /// 下载服务返回的图片链接（本地 http 也可以）
  Future<Uint8List> _download(String url, TryonConfig c) async {
    final dr = await http
        .get(Uri.parse(url), headers: _headers(c))
        .timeout(_genTimeout);
    if (dr.statusCode >= 200 && dr.statusCode < 300) return dr.bodyBytes;
    throw Exception('试穿图下载失败（${dr.statusCode}）');
  }

  /// 错误响应里的描述：OpenAI 风格 error 是对象，其余当字符串
  String _errDetail(Map<String, dynamic>? json) {
    final e = json?['error'] ?? json?['message'];
    if (e is String) return e;
    if (e is Map) {
      final m = e['message'];
      if (m is String && m.isNotEmpty) return m;
    }
    return '';
  }

  String _short(Object e) {
    var msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return msg.length > 90 ? '${msg.substring(0, 90)}…' : msg;
  }
}
