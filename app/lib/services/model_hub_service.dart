// 自部署模型中心 —— 填 baseUrl + API Key，刷新出模型清单，按能力挑模型
//
// 为什么独立成这个模块（而不是塞进 tryon_service.dart）：
//   tryon_service.dart 的职责是「试衣协议的直连客户端」，只该关心试衣那一个 POST；
//   而这里是「连接一个 OpenAI 兼容端点并管理多能力模型选择」的通用能力，
//   文本润色、图像试衣、视频、TTS 都会复用它。混在一起两边都难维护。
//
// 定位（与 tryon_service 一致的隐私红线）：
//   - 端点由用户自行部署（本地电脑 / 局域网 / 自有服务器），App 只做直连；
//   - baseUrl / apiKey / 选中的模型名**只存手机本地**（SharedPreferences），不上传、不入库；
//   - 拉模型清单只发一个 GET /models，不携带任何图片与衣橱数据。
//
// 协议（OpenAI 兼容为主，兼容 Ollama 与若干自建端点）：
//   拉清单：依次尝试 {base}/models → {base}/v1/models → {base}/api/tags，首个成功即用
//     - OpenAI 风格：{"data":[{"id":"gpt-4o"}]}或 {"data":["gpt-4o"]}
//     - Ollama 风格：{"models":[{"name":"llama3:latest"}]}
//     - 裸数组：[...] 也能认
//   鉴权：Authorization: Bearer {apiKey}；部分自建服务只认 X-API-Key，故两者都带上（无害）
//   生成（图像）：POST {base}/v1/images/generations，body 走 OpenAI 兼容格式
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 模型能力分类 —— 建议按这四类配置，各自独立选一个模型
enum ModelKind {
  text('文本', '搭配理由、衣柜分析、导入解析'),
  image('图像', '虚拟试衣出图、单品抠图'),
  video('视频', '动态走秀、短视频素材'),
  tts('TTS', '语音念出搭配理由');

  const ModelKind(this.label, this.usage);

  final String label; // 短标签，用于 UI
  final String usage; // 一句话说明这个能力会用在哪儿
}

/// 自部署模型中心配置（全部只存本地）
class ModelHubConfig {
  const ModelHubConfig({
    this.enabled = false,
    this.baseUrl = '',
    this.apiKey = '',
    this.textModel = '',
    this.imageModel = '',
    this.videoModel = '',
    this.ttsModel = '',
    this.tryonPath = '/tryon',
  });

  final bool enabled;
  final String baseUrl; // 如 https://api.example.com/v1 或 http://192.168.1.5:11434
  final String apiKey; // 可选
  final String textModel; // 选中的模型 id（空 = 该能力不启用）
  final String imageModel;
  final String videoModel;
  final String ttsModel;

  /// 自定义试衣端点路径。默认 /tryon 是本项目自研协议（见 docs/tryon-api.md）；
  /// 若你的服务是 OpenAI 兼容图像接口，清空它即可走/v1/images/generations。
  final String tryonPath;

  bool get baseOk => normalizeBase(baseUrl) != null;

  /// 至少配了一个能力才叫「配好了」
  bool get anyModelPicked =>
      textModel.isNotEmpty ||
      imageModel.isNotEmpty ||
      videoModel.isNotEmpty ||
      ttsModel.isNotEmpty;

  bool get isReady => enabled && baseOk;

  String modelOf(ModelKind k) {
    switch (k) {
      case ModelKind.text:
        return textModel;
      case ModelKind.image:
        return imageModel;
      case ModelKind.video:
        return videoModel;
      case ModelKind.tts:
        return ttsModel;
    }
  }

  ModelHubConfig copyWith({
    bool? enabled,
    String? baseUrl,
    String? apiKey,
    String? textModel,
    String? imageModel,
    String? videoModel,
    String? ttsModel,
    String? tryonPath,
  }) {
    return ModelHubConfig(
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      textModel: textModel ?? this.textModel,
      imageModel: imageModel ?? this.imageModel,
      videoModel: videoModel ?? this.videoModel,
      ttsModel: ttsModel ?? this.ttsModel,
      tryonPath: tryonPath ?? this.tryonPath,
    );
  }

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
}

/// 拉模型清单的结果
class ModelListResult {
  const ModelListResult({
    required this.models,
    required this.endpointUsed,
    this.error,
  });

  final List<String> models; // 去重后的模型 id
  final String endpointUsed; // 实际命中的端点，便于排查
  final String? error; // 人话化错误，成功时为 null
  bool get ok => error == null && models.isNotEmpty;
}

/// 自部署模型中心的直连客户端
class ModelHubService {
  ModelHubService();

  // SharedPreferences keys（前缀 mh_，与 tryon_* 完全隔离）
  static const _kEnabled = 'mh_enabled';
  static const _kBase = 'mh_base_url';
  static const _kKey = 'mh_api_key';
  static const _kText = 'mh_model_text';
  static const _kImage = 'mh_model_image';
  static const _kVideo = 'mh_model_video';
  static const _kTts = 'mh_model_tts';
  static const _kPath = 'mh_tryon_path';

  /// 拉清单超时：本地/局域网服务很快，云端端点留 15s
  static const Duration _listTimeout = Duration(seconds: 15);

  static Future<ModelHubConfig> loadConfig() async {
    final sp = await SharedPreferences.getInstance();
    return ModelHubConfig(
      enabled: sp.getBool(_kEnabled) ?? false,
      baseUrl: sp.getString(_kBase) ?? '',
      apiKey: sp.getString(_kKey) ?? '',
      textModel: sp.getString(_kText) ?? '',
      imageModel: sp.getString(_kImage) ?? '',
      videoModel: sp.getString(_kVideo) ?? '',
      ttsModel: sp.getString(_kTts) ?? '',
      tryonPath: sp.getString(_kPath) ?? '/tryon',
    );
  }

  static Future<void> saveConfig(ModelHubConfig c) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kEnabled, c.enabled);
    await sp.setString(_kBase, c.baseUrl.trim());
    await sp.setString(_kKey, c.apiKey.trim());
    await sp.setString(_kText, c.textModel.trim());
    await sp.setString(_kImage, c.imageModel.trim());
    await sp.setString(_kVideo, c.videoModel.trim());
    await sp.setString(_kTts, c.ttsModel.trim());
    await sp.setString(_kPath, c.tryonPath.trim().isEmpty ? '/tryon' : c.tryonPath.trim());
  }

  Map<String, String> _headers(ModelHubConfig c) => {
        'Accept': 'application/json',
        if (c.apiKey.isNotEmpty) 'Authorization': 'Bearer ${c.apiKey.trim()}',
        // 不少自建网关（如 one-api 系）只认 X-API-Key，带上它无害
        if (c.apiKey.isNotEmpty) 'X-API-Key': c.apiKey.trim(),
      };

  /// 候选端点：用户可能填了带 /v1 的完整地址，也可能只填到根，逐个试
  static List<String> _candidateEndpoints(String base) {
    final endsV1 = base.endsWith('/v1');
    return [
      if (endsV1) '$base/models',
      '$base/v1/models',
      if (!endsV1) '$base/models',
      '$base/api/tags', // Ollama 原生
    ];
  }

  /// 刷新模型清单：按候选端点依次尝试，首个成功即返回
  Future<ModelListResult> fetchModels(ModelHubConfig c) async {
    final base = ModelHubConfig.normalizeBase(c.baseUrl);
    if (base == null) {
      return const ModelListResult(
        models: [],
        endpointUsed: '',
        error: '服务地址不合法，要以 http:// 或 https:// 开头',
      );
    }

    final tried = <String>[];
    Object? lastErr;

    for (final ep in _candidateEndpoints(base)) {
      final uri = Uri.tryParse(ep);
      if (uri == null) continue;
      tried.add(ep);
      try {
        final r = await http
            .get(uri, headers: _headers(c))
            .timeout(_listTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final models = _parseModels(r.body);
          if (models.isNotEmpty) {
            return ModelListResult(models: models, endpointUsed: ep);
          }
          lastErr = '连上了但没解析出模型名（返回的不是模型清单）';
          continue;
        }
        if (r.statusCode == 401 || r.statusCode == 403) {
          return ModelListResult(
            models: [],
            endpointUsed: ep,
            error: '鉴权被拒（$ep 返回 ${r.statusCode}），检查 API Key 填对没有',
          );
        }
        lastErr = '${Uri.parse(ep).path} 返回 ${r.statusCode}';
      } on TimeoutException {
        lastErr = '${Uri.parse(ep).path} 15 秒没响应';
      } catch (e) {
        // 浏览器端 CORS 拦截会走到这里，单独给一句人话
        lastErr = _friendlyNetError(e, Uri.parse(ep));
      }
    }

    return ModelListResult(
      models: [],
      endpointUsed: tried.isEmpty ? '' : tried.first,
      error: '没拉到模型清单（试过 ${tried.length} 个常见路径）。'
          '${lastErr ?? ''}。若你自建的服务就是没有 /models 接口，可在下方「手动填写模型名」。',
    );
  }

  /// 兼容 OpenAI / Ollama / 裸数组三种返回
  static List<String> _parseModels(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const [];
    }

    List<Object?> raw = const [];
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map) {
      final m = decoded;
      final d = m['data'] ?? m['models'] ?? m['result'] ?? m['items'];
      if (d is List) {
        raw = d;
      } else if (d is Map) {
        // 少数网关返回 {"data":{"models":[...]}}
        final inner = d['models'];
        if (inner is List) raw = inner;
      }
    }

    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      String? id;
      if (item is String) {
        id = item;
      } else if (item is Map) {
        final v = item['id'] ?? item['name'] ?? item['model'];
        if (v is String) id = v;
      }
      final name = id?.trim() ?? '';
      if (name.isEmpty) continue;
      // Ollama 会把 "llama3:latest" 与 "llama3:latest" 重复列出，去重但保序
      if (seen.add(name)) out.add(name);
    }
    return out;
  }

  /// 把异常翻译成人话；浏览器 CORS 拦截时给专门的提示
  static String _friendlyNetError(Object e, Uri uri) {
    final s = e.toString();
    if (s.contains('XMLHttpRequest') || s.contains('statusCode: 0') || s.contains('CORS')) {
      return '${uri.path} 被浏览器拦了（CORS）——服务要允许跨域：'
          'Ollama 设 OLLAMA_ORIGINS=*，或用反代加 CORS 头。'
          '手机 App 不受此限。';
    }
    var msg = s.replaceFirst(RegExp(r'^(ClientException|Exception|FormatException)\s*:\s*'), '');
    if (msg.length > 90) msg = '${msg.substring(0, 90)}…';
    return msg;
  }

  // ==================== 能力分类启发式 ====================

  /// 按模型名猜能力。**这是建议，不是结论** —— 所以 UI 永远给「手动改」选项。
  /// 匹配顺序刻意把 video 放最前：像 "sora-2" 这类名字里同时含 text 特征词，
  /// 若先判文本会误分；tts 同理要抢在 text 前（"whisper" 名字里没有 text 词，但保险）。
  static ModelKind guessKind(String modelId) {
    final id = modelId.toLowerCase();
    if (_videoHints.any(id.contains)) return ModelKind.video;
    if (_ttsHints.any(id.contains)) return ModelKind.tts;
    if (_imageHints.any(id.contains)) return ModelKind.image;
    return ModelKind.text; // 兜底：LLM/chat/embedding 之类都算文本
  }

  /// 该能力下的推荐模型（按启发式 + 顺序），供 UI 展示「推荐」分组
  static List<String> recommend(List<String> models, ModelKind kind) {
    final same = models.where((m) => guessKind(m) == kind).toList();
    return same;
  }

  // ==================== 穿搭识别（一图拆多件） ====================

  /// 识别提示词：让模型既说清每件是什么，也给出大致位置便于裁剪。
  /// 特意要求**宁多不少**，多报几件由用户勾选删除，比漏报强。
  static const _analyzePrompt = '''
你是一位专业的服装造型师。我给你一张穿着全身搭配的照片，请把它拆成独立的衣物。

对每一件可见衣物输出：
- name：中文衣物名，6 字以内，带颜色前缀，如「米色风衣」「白色针织衫」
- category：从 tops(上装) / bottoms(下装) / dress(连衣裙) / outerwear(外套) / shoes(鞋子) / bag(包袋) / accessories(配饰) 中选一个
- color：中文颜色词，如米色、藏蓝、燕麦
- box：衣物在这张图里的位置，用 0~1000 的相对坐标表示 [左, 上, 右, 下]
- confidence：0~1 的置信度

规则：
1. 只要能独立穿脱、或在搭配里承担独立角色，就单列出来。外套和里面的上衣要分开算。
2. 鞋子、包、帽子、围巾、腰带都单独列出。
3. 首饰、妆容、发型不要列。
4. 如果只是同一套的印花图案变化（比如两件同款上衣），只列一次。
5. box 要紧贴衣物边缘，不要包含大片背景或人体其他部位。
6. 最多 12 件。只输出 JSON，不要任何解释文字。

输出格式：{"garments":[{"name":"...","category":"...","color":"...","box":[l,t,r,b],"confidence":0.9}]}''';

  /// 识别超时：多模态模型读图 + 思考，60s 起步
  static const Duration _analyzeTimeout = Duration(seconds: 90);

  /// 识别一图中的多件衣物。
  ///
  /// 走 OpenAI 兼容的 vision 接口：POST {base}/chat/completions，
  /// 图片以 data URL 内联。返回的 box 供调用方裁剪出单品图。
  Future<OutfitAnalysis> analyzeOutfit({
    required ModelHubConfig c,
    required Uint8List image,
    required String mimeType,
  }) async {
    final base = ModelHubConfig.normalizeBase(c.baseUrl);
    if (base == null) {
      return const OutfitAnalysis(
          garments: [], warning: '服务地址不合法，先去设置里填 baseUrl');
    }
    final model = c.textModel.isNotEmpty ? c.textModel : c.imageModel;
    if (model.isEmpty) {
      return const OutfitAnalysis(
          garments: [], warning: '没选模型。去设置 → 自部署模型，挑一个能读图的（多模态）模型');
    }

    final root = base.endsWith('/v1') ? base : '$base/v1';
    final uri = Uri.tryParse('$root/chat/completions');
    if (uri == null) {
      return const OutfitAnalysis(garments: [], warning: '拼接请求地址失败');
    }

    final dataUrl = 'data:$mimeType;base64,${base64Encode(image)}';
    final body = jsonEncode({
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content': '你只输出 JSON，不输出任何解释。即使不确定也给出最可能的猜测。',
        },
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _analyzePrompt},
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        },
      ],
      'temperature': 0.2,
      'max_tokens': 1500,
    });

    http.Response r;
    try {
      r = await http.post(uri, headers: {
        'Content-Type': 'application/json',
        if (c.apiKey.isNotEmpty) 'Authorization': 'Bearer ${c.apiKey.trim()}',
        if (c.apiKey.isNotEmpty) 'X-API-Key': c.apiKey.trim(),
      }, body: body).timeout(_analyzeTimeout);
    } on TimeoutException {
      return const OutfitAnalysis(garments: [], warning: '等了 90 秒模型还没回，可能是模型太大或显卡不够');
    } catch (e) {
      return OutfitAnalysis(garments: [], warning: '请求发不出去：${_friendlyNetError(e, uri)}');
    }

    if (r.statusCode < 200 || r.statusCode >= 300) {
      // 400 常见于「这个模型不支持图片」，给一句能照做的提示
      final detail = _errorDetailOf(r);
      final hint = r.statusCode == 400 && detail.toLowerCase().contains('image')
          ? '这个模型读不了图片（$detail）。换个多模态模型试试，比如 qwen2.5-vl、gpt-4o。'
          : '服务返回 ${r.statusCode}${detail.isEmpty ? '' : '：$detail'}';
      return OutfitAnalysis(garments: [], warning: hint);
    }

    try {
      final text = _extractContent(r.body);
      if (text == null || text.isEmpty) {
        return const OutfitAnalysis(garments: [], warning: '模型没返回内容');
      }
      final list = _parseGarmentList(text);
      if (list == null) {
        return OutfitAnalysis(
            garments: [], warning: '模型没按 JSON 格式回（可能不是多模态模型）。原文开头：${_head(text)}');
      }
      final sorted = [...list]..sort((a, b) => b.confidence.compareTo(a.confidence));
      return OutfitAnalysis(
        garments: sorted,
        warning: sorted.isEmpty
            ? '没在这张图里认出衣物。换一张更清晰、人物更完整的照片试试'
            : (sorted.length == 1 ? '只认出 1 件。合照或穿搭图通常能拆出更多' : null),
      );
    } catch (e) {
      return OutfitAnalysis(garments: [], warning: '解析模型结果出错：$e');
    }
  }

  /// 从 chat/completions 响应里取出 content（兼容 content 为数组的多模态返回）
  @visibleForTesting
  static String? extractContentForTest(String body) => _extractContent(body);

  static String? _extractContent(String body) {
    final j = jsonDecode(body);
    if (j is! Map) return null;
    final choices = j['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final msg = (choices.first as Map)['message'] ?? (choices.first as Map)['delta'];
    if (msg is! Map) return null;
    final content = msg['content'] ?? msg['reasoning_content'];
    if (content is String) return content;
    if (content is List) {
      // 多模态端点常返回 [{type:'text',text:'...'}]
      final buf = StringBuffer();
      for (final p in content) {
        if (p is Map && p['text'] is String) buf.write(p['text']);
      }
      return buf.toString();
    }
    return null;
  }

  /// 从模型回复里抠出 garments 数组。
  /// 不要求模型输出纯 JSON —— 很多模型会带 markdown 围栏或前后废话，故做容错。
  ///
  /// 标注 visibleForTesting：这是全项目**最脆弱**的一段解析（模型输出格式
  /// 不可控、容错分支多），必须有单测兜住，否则改坏了要等线上才发现。
  @visibleForTesting
  static List<DetectedGarment>? parseGarmentListForTest(String text) =>
      _parseGarmentList(text);

  static List<DetectedGarment>? _parseGarmentList(String text) {
    var s = text.trim();
    // 剥 markdown 围栏
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final fm = fence.firstMatch(s);
    if (fm != null) s = fm.group(1)!.trim();

    dynamic parsed;
    try {
      parsed = jsonDecode(s);
    } catch (_) {
      // 退化：直接抓第一个 {...} 块
      final start = s.indexOf('{');
      final end = s.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      try {
        parsed = jsonDecode(s.substring(start, end + 1));
      } catch (_) {
        return null;
      }
    }

    List<Object?> arr;
    if (parsed is List) {
      arr = parsed;
    } else if (parsed is Map) {
      final g = parsed['garments'] ?? parsed['items'] ?? parsed['clothes'] ?? parsed['result'];
      if (g is List) {
        arr = g;
      } else if (parsed.isNotEmpty && parsed['name'] != null) {
        arr = [parsed]; // 只有一个对象而非数组
      } else {
        return null;
      }
    } else {
      return null;
    }

    final out = <DetectedGarment>[];
    for (final e in arr) {
      if (e is Map) {
        // jsonDecode 给出的是 Map<dynamic,dynamic>，这里转成目标类型再进fromJson
        final g = DetectedGarment.fromJson(Map<String, dynamic>.from(e));
        if (g.name.isNotEmpty) out.add(g);
      }
    }
    return out;
  }

  /// 错误响应里的描述
  static String _errorDetailOf(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      if (j is Map) {
        final e = j['error'];
        if (e is String) return e;
        if (e is Map && e['message'] is String) return e['message'];
        if (j['message'] is String) return j['message'];
      }
    } catch (_) {/* 非 JSON 就算了 */}
    return '';
  }

  static String _head(String s) =>
      s.length > 60 ? '${s.substring(0, 60)}…' : s;

  static const _videoHints = [
    'video', 'sora', 'veo', 'kling', '可灵', 'runway', 'pika', 'luma',
    'hunyuan-video', 'cogvideo', 'wan2', 'mochi', 'vidu', 'hailuo', 'minimax-video',
  ];
  static const _ttsHints = [
    'tts', 'speech', 'whisper', 'bark', 'cosyvoice', 'fish-speech', 'fishspeech',
    'edge-tts', 'elevenlabs', 'kokoro', 'vits', 'piper', 'gtts', 'melo', 'xtts',
    'openaudio', 'voice',
  ];
  static const _imageHints = [
    'image', 'img2img', 'txt2img', 't2i', 'i2i', 'dall-e', 'dalle', 'flux',
    'stable-diffusion', 'stablediffusion', 'sdxl', 'sd3', 'midjourney', 'ideogram',
    'recraft', 'kolors', 'imagen', 'lcm', 'dreamshaper', 'instantid', 'ip-adapter',
    'controlnet', 'nanobanana',
  ];
}

/// 识别出的一件衣物
class DetectedGarment {
  const DetectedGarment({
    required this.name,
    required this.categoryHint,
    this.colorName = '',
    this.box,
    this.confidence = 0,
  });

  final String name; // 如「米色风衣」
  final String categoryHint; // 建议分类，如 outerwear
  final String colorName; // 如「米色」
  /// 归一化坐标 [left, top, width, height]，取值 0~1（相对原图）。
  /// 模型没给就为 null，此时「用原图」而非裁剪。
  final List<double>? box;
  final double confidence; // 0~1，模型自评，仅用于排序

  factory DetectedGarment.fromJson(Map<String, dynamic> j) {
    List<double>? b;
    final raw = j['box'] ?? j['bbox'] ?? j['rect'];
    if (raw is List) {
      final v = raw.map((e) => (e is num ? e.toDouble() : double.tryParse('$e') ?? -1)).toList();
      // 有的模型给 [x1,y1,x2,y2]（两点式），这里只当宽高式用，
      // 两点式会在下面 crop 时按宽高解释，由调用方限制在图内即可
      if (v.length >= 4 && v.every((e) => e >= 0)) {
        b = [v[0] / 1000, v[1] / 1000, (v[2] - v[0]) / 1000, (v[3] - v[1]) / 1000];
      }
    } else if (raw is Map) {
      final l = _d(raw['left'] ?? raw['x'] ?? raw['x1']);
      final t = _d(raw['top'] ?? raw['y'] ?? raw['y1']);
      final w = _d(raw['width'] ?? raw['w']);
      final h = _d(raw['height'] ?? raw['h']);
      if (l != null && t != null && w != null && h != null) {
        b = [l, t, w, h];
      }
    }
    return DetectedGarment(
      name: (j['name'] ?? j['item'] ?? j['title'] ?? '').toString().trim(),
      categoryHint: (j['category'] ?? j['categoryHint'] ?? j['type'] ?? '').toString().trim(),
      colorName: (j['color'] ?? j['colorName'] ?? '').toString().trim(),
      box: b,
      confidence: _d(j['confidence'] ?? j['score'] ?? j['prob']) ?? 0,
    );
  }

  static double? _d(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('$v');
}

/// 穿搭识别结果
class OutfitAnalysis {
  const OutfitAnalysis({required this.garments, this.warning});

  final List<DetectedGarment> garments;
  final String? warning; // 非致命提示，如「只识别到 1 件」

  bool get ok => garments.isNotEmpty;
}
