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

/// 用户在设置里维护的试衣服务配置（仅存本地）
class TryonConfig {
  const TryonConfig({
    this.enabled = false,
    this.baseUrl = '',
    this.path = '/tryon',
    this.apiKey = '',
  });

  final bool enabled;
  final String baseUrl; // 如 http://192.168.1.5:8000
  final String path; // 生成接口路径，默认 /tryon
  final String apiKey; // 可选，将以 X-API-Key 头发送

  bool get isReady =>
      enabled && _normalizeBase(baseUrl) != null && path.trim().isNotEmpty;

  /// 规范化 baseUrl：去尾斜杠 + 校验 http/https
  static String? _normalizeBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.startsWith('http://') && !s.startsWith('https://')) return null;
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return Uri.tryParse(s)?.host.isEmpty == false ? s : null;
  }

  Uri? healthUri() {
    final base = _normalizeBase(baseUrl);
    return base == null ? null : Uri.parse('$base/health');
  }

  Uri? generateUri() {
    final base = _normalizeBase(baseUrl);
    final p = path.trim().isEmpty ? '/tryon' : path.trim();
    if (base == null || !p.startsWith('/')) return null;
    return Uri.parse('$base$p');
  }
}

/// 可选身体数据（cm / kg），全可空，用户愿填才随请求发送
class TryonBodyData {
  const TryonBodyData({
    this.heightCm,
    this.weightKg,
    this.bust,
    this.waist,
    this.hips,
  });

  final double? heightCm;
  final double? weightKg;
  final double? bust;
  final double? waist;
  final double? hips;

  Map<String, double?> toJson() => {
        'heightCm': heightCm,
        'weightKg': weightKg,
        'bust': bust,
        'waist': waist,
        'hips': hips,
      };
}

class TryonService {
  TryonService();

  // SharedPreferences keys
  static const _kEnabled = 'tryon_enabled';
  static const _kBase = 'tryon_base_url';
  static const _kPath = 'tryon_path';
  static const _kKey = 'tryon_api_key';

  /// 生成接口超时：本地模型出图慢（30s~3min 常见），给足余量
  static const Duration _genTimeout = Duration(seconds: 180);
  static const Duration _pingTimeout = Duration(seconds: 10);

  static Future<TryonConfig> loadConfig() async {
    final sp = await SharedPreferences.getInstance();
    return TryonConfig(
      enabled: sp.getBool(_kEnabled) ?? false,
      baseUrl: sp.getString(_kBase) ?? '',
      path: sp.getString(_kPath) ?? '/tryon',
      apiKey: sp.getString(_kKey) ?? '',
    );
  }

  static Future<void> saveConfig(TryonConfig c) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kEnabled, c.enabled);
    await sp.setString(_kBase, c.baseUrl.trim());
    await sp.setString(_kPath, c.path.trim().isEmpty ? '/tryon' : c.path.trim());
    await sp.setString(_kKey, c.apiKey.trim());
  }

  Map<String, String> _headers(TryonConfig c) => {
        'Content-Type': 'application/json',
        if (c.apiKey.isNotEmpty) 'X-API-Key': c.apiKey,
      };

  /// 连接测试：GET {baseUrl}/health，任意 2xx 即在线
  /// 返回 null 表示成功（在线），否则返回给用户的错误文案
  Future<String?> testConnection(TryonConfig c) async {
    final uri = c.healthUri();
    if (uri == null) return '服务地址不合法，要以 http:// 或 https:// 开头';
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
  Future<Uint8List> generate({
    required TryonConfig c,
    required List<Uint8List> personImages,
    required Uint8List garmentImage,
    Uint8List? poseImage,
    TryonBodyData? body,
    String? prompt,
    Map<String, Object?>? options,
  }) async {
    final uri = c.generateUri();
    if (uri == null) throw Exception('试衣服务未配置好：去设置里检查服务地址与接口路径');
    if (personImages.isEmpty) throw Exception('至少要一张人像照');
    if (personImages.length > 5) throw Exception('人像最多 5 张');

    final payload = <String, Object?>{
      'personImages': personImages.map(base64Encode).toList(),
      'garmentImage': base64Encode(garmentImage),
      'poseImage': poseImage == null ? null : base64Encode(poseImage),
      'body': body?.toJson(),
      'prompt': prompt,
      'options': options,
    };

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
      final detail = json?['error'] ?? json?['message'] ?? '';
      throw Exception('服务返回 ${r.statusCode}${detail == '' ? '' : '：$detail'}');
    }
    if (json == null) throw Exception('服务返回了看不懂的内容（非 JSON 也非图片）');

    // 兼容 a)：{"image": "<base64>"}
    final img = json['image'];
    if (img is String && img.isNotEmpty) {
      return base64Decode(img.startsWith('data:') ? img.split(',').last : img);
    }
    // 兼容 b)：{"imageUrl": "..."}
    final url = json['imageUrl'] ?? json['image_url'];
    if (url is String && url.isNotEmpty) {
      final dr = await http
          .get(Uri.parse(url), headers: _headers(c))
          .timeout(_genTimeout);
      if (dr.statusCode >= 200 && dr.statusCode < 300) return dr.bodyBytes;
      throw Exception('试穿图下载失败（${dr.statusCode}）');
    }
    final err = json['error'] ?? json['message'];
    throw Exception(err is String && err.isNotEmpty ? err : '服务没返回图片字段');
  }

  String _short(Object e) {
    var msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return msg.length > 90 ? '${msg.substring(0, 90)}…' : msg;
  }
}
