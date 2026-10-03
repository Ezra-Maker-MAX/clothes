// 设置页 —— 目前承载「自部署模型中心」配置区 + 天气城市 + 批量导入 + 关于
//
// 设计原则：
// - 模型服务是用户自己的端点（本地电脑 / 局域网 / 自有服务器 / 云端 OpenAI 兼容网关），
//   配置只存手机本地（SharedPreferences），不上传、不入库；
// - 交互沿用公版大模型客户端的惯用套路：填 baseUrl + API Key → 刷新出模型清单 → 下拉挑选；
// - 图片与请求只从手机直发该地址，不经过衣念服务端 —— 云端零留存（详见 tryon_service.dart 头注释）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/tryon_page.dart';
import '../services/api_client.dart';
import '../services/model_hub_service.dart';
import '../services/tryon_service.dart';
import '../theme/app_colors.dart';
import '../widgets/peach_secret_entrance.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ModelHubConfig _config = const ModelHubConfig();
  bool _loaded = false;
  bool _refreshing = false;
  bool _testing = false;
  bool _importing = false;
  Timer? _saveDebounce;

  /// 上次刷到的模型清单；下拉选项从这里来
  List<String> _models = const [];
  /// 刷新结果提示（成功/失败原因），直接显示在卡片里
  String? _refreshNote;
  bool _refreshOk = false;

  final _baseCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  final _orderCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  bool _keyVisible = false;
  // 注：🍑 隐蔽入口的连点计数与计时器已随逻辑一并迁到
  // widgets/peach_secret_entrance.dart，由那个 widget 自己管理生命周期。

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _baseCtrl.dispose();
    _keyCtrl.dispose();
    _pathCtrl.dispose();
    _orderCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await ModelHubService.loadConfig();
    final city = await ApiClient.weatherCity();
    if (!mounted) return;
    setState(() {
      _config = c;
      _baseCtrl.text = c.baseUrl;
      _keyCtrl.text = c.apiKey;
      _pathCtrl.text = c.tryonPath;
      _cityCtrl.text = city;
      _loaded = true;
    });
  }

  /// 保存常驻城市（空串 = 服务端按访问 IP 自动定位）
  Future<void> _saveCity({bool clear = false}) async {
    final v = clear ? '' : _cityCtrl.text.trim();
    await ApiClient.setWeatherCity(v);
    if (!mounted) return;
    if (clear) _cityCtrl.clear();
    _snack(clear ? '已切回自动定位' : (v.isEmpty ? '已切回自动定位' : '城市已设为「$v」'));
  }

  /// 字段变更 → 防抖 800ms 落盘（输入过程不频繁写盘）
  void _update(ModelHubConfig next) {
    setState(() => _config = next);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      ModelHubService.saveConfig(_config);
    });
  }

  /// 刷新模型清单：拿当前输入的 baseUrl + key 去问服务端要模型名
  Future<void> _refreshModels() async {
    final probe = _config.copyWith(
      baseUrl: _baseCtrl.text,
      apiKey: _keyCtrl.text,
    );
    if (!probe.baseOk) {
      setState(() {
        _refreshOk = false;
        _refreshNote = '先填服务地址，要以 http:// 或 https:// 开头';
      });
      return;
    }
    setState(() {
      _refreshing = true;
      _refreshNote = null;
    });
    final r = await ModelHubService().fetchModels(probe);
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _models = r.models;
      _refreshOk = r.ok;
      _refreshNote = r.ok
          ? '拉到 ${r.models.length} 个模型 · ${Uri.parse(r.endpointUsed).path}'
          : r.error;
      // 地址/Key 顺手落盘，免得多点一次保存
      if (r.ok) _update(_config.copyWith(baseUrl: _baseCtrl.text, apiKey: _keyCtrl.text));
    });
    if (r.ok) {
      // 一条命令都没选的，给个默认预选：每种能力挑第一个推荐的
      var next = _config.copyWith(baseUrl: _baseCtrl.text, apiKey: _keyCtrl.text);
      for (final k in ModelKind.values) {
        if (next.modelOf(k).isNotEmpty) continue;
        final rec = ModelHubService.recommend(r.models, k);
        next = _applyModel(next, k, rec.isEmpty ? '' : rec.first);
      }
      if (mounted) setState(() => _config = next);
      await ModelHubService.saveConfig(next);
    }
  }

  ModelHubConfig _applyModel(ModelHubConfig c, ModelKind k, String model) {
    switch (k) {
      case ModelKind.text:
        return c.copyWith(textModel: model);
      case ModelKind.image:
        return c.copyWith(imageModel: model);
      case ModelKind.video:
        return c.copyWith(videoModel: model);
      case ModelKind.tts:
        return c.copyWith(ttsModel: model);
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final err = await TryonService().testConnection(
      baseUrl: _baseCtrl.text,
      apiKey: _keyCtrl.text,
    );
    if (!mounted) return;
    setState(() => _testing = false);
    _snack(err ?? '服务在线，可以开试👌');
  }

  void _openTryon() {
    if (!_config.baseOk) {
      _snack('先把服务地址填好');
      return;
    }
    if (_config.imageModel.isEmpty) {
      _snack('还没选图像模型，展开「图像」挑一个，或者直接进试衣间让后端自己决定');
    }
    // 进试衣间前确保落盘（试衣页会读模型中心配置）
    ModelHubService.saveConfig(_config.copyWith(
      enabled: true,
      baseUrl: _baseCtrl.text,
      apiKey: _keyCtrl.text,
      tryonPath: _pathCtrl.text,
    ));
    Navigator.push(context, MaterialPageRoute(builder: (_) => const TryonPage()));
  }

  // ---------------------------------------------------------------
  // 私密空间（内衣模式）：密码存在 Vercel 环境变量 PRIVATE_MODE_PASSWORD，
  // App 与本地存储均无密码明文；解锁后全 App 切换暗夜酒红主题。
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textMain),
        ),
        title: Text('设置',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        centerTitle: true,
      ),
      body: !_loaded
          ? Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                _sectionTitle('天气 · 常驻城市', '精准推荐'),
                _cityCard(),
                const SizedBox(height: 20),
                _sectionTitle('自部署模型', '本地优先'),
                _modelHubCard(),
                const SizedBox(height: 20),
                _sectionTitle('批量导入', '省事'),
                _importCard(),
                const SizedBox(height: 20),
                _sectionTitle('关于', null),
                _aboutCard(),
                const SizedBox(height: 16),
                // 页脚说明：末尾的 🍑 是私密空间的隐蔽入口（连点 5 次），
                // 融在文案里就是一枚普通表情，旁人看不出任何门道。
                // 逻辑已抽到 widgets/peach_secret_entrance.dart —— 隐私关键代码
                // 不该埋在一千多行的设置页里，改版时容易被顺手改掉。
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text.rich(
                    TextSpan(
                      text: '你的衣橱数据与模型配置都只属于你：'
                          '衣橱数据存放在你自己的数据库，模型请求只发往你自己填的服务地址。',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textHint,
                          height: 1.6),
                      children: const [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: PeachSecretEntrance(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// 订单文本批量导入：粘贴订单商品行 → /api/import-order 解析 → 批量建单品
  Future<void> _importOrders() async {
    final text = _orderCtrl.text.trim();
    if (text.isEmpty) {
      _snack('先粘贴订单里的商品行，每行一件');
      return;
    }
    setState(() => _importing = true);
    try {
      final r = await ApiClient.importOrderText(text);
      if (!mounted) return;
      _orderCtrl.clear();
      _snack(r.unknownCategories.isEmpty
          ? '导入了 ${r.imported} 件，去衣橱看看'
          : '导入了 ${r.imported} 件；其中「${r.unknownCategories.take(2).join('、')}${r.unknownCategories.length > 2 ? '等' : ''}」分类是猜的，顺手改一下');
    } catch (e) {
      if (mounted) {
        var msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        if (msg.length > 80) msg = '${msg.substring(0, 80)}…';
        _snack('没导进去：$msg');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _importCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.playlist_add_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('从订单文本导入',
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textMain)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('把购物 App 订单里的商品名一行一个粘进来，自动识别分类与价格后批量入橱。',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSub, height: 1.5)),
          const SizedBox(height: 10),
          TextField(
            controller: _orderCtrl,
            maxLines: 5,
            style: TextStyle(fontSize: 13, color: AppColors.textMain),
            decoration: InputDecoration(
              hintText: '云朵白衬衫 299\n高腰直筒牛仔裤 459\n裸色平底穆勒鞋 368',
              hintStyle: TextStyle(fontSize: 12, color: AppColors.textHint),
              filled: true,
              fillColor: AppColors.bg,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _importing ? null : _importOrders,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
              icon: _importing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(_importing ? '正在导入…' : '解析并导入衣橱',
                  style: const TextStyle(fontSize: 13.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String? badge) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 10),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textMain)),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(badge,
                  style: TextStyle(fontSize: 10.5, color: AppColors.accent)),
            ),
          ],
        ],
      ),
    );
  }

  /// 常驻城市：留空 = 服务端按访问 IP 自动定位（推荐）；填城市名 = 以你填的为准
  Widget _cityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('你所在的城市',
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textMain)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('留空 = 按当前网络自动定位（推荐，桌面和手机都生效）；'
              '填城市名则以你填的为准，出差/跨城时更准。',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSub, height: 1.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _cityCtrl,
            style: TextStyle(fontSize: 13, color: AppColors.textMain),
            decoration: InputDecoration(
              hintText: '留空自动定位，或填：杭州 / Beijing',
              hintStyle: TextStyle(fontSize: 12, color: AppColors.textHint),
              filled: true,
              fillColor: AppColors.bg,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _saveCity(clear: true),
                child: Text('清空，自动定位',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () => _saveCity(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('保存', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 自部署模型中心：地址 + Key → 刷新模型 → 四类能力各选一个
  Widget _modelHubCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 开关行
            Row(
              children: [
                Icon(Icons.hub_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('启用自部署模型',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMain)),
                ),
                Switch(
                  value: _config.enabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => _update(_config.copyWith(enabled: v)),
                ),
              ],
            ),
            Text('接你自己的模型服务。填好地址和 Key，点「刷新模型」就会把它有哪些模型拉下来，'
                '再按文本 / 图像 / 视频 / TTS 挑。',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSub, height: 1.5)),

            // ---- 连接信息 ----
            _field(_baseCtrl, '服务地址 Base URL', 'http://192.168.1.5:11434',
                onChanged: (s) => _update(_config.copyWith(baseUrl: s))),
            _keyField(),
            _field(_pathCtrl, '试衣接口路径（留空 = OpenAI 兼容）', '/tryon',
                helper: '自研协议填 /tryon；用 OpenAI 兼容图像接口就清空，'
                    'App 会走 /v1/images/generations',
                onChanged: (s) => _update(_config.copyWith(tryonPath: s))),

            // ---- 刷新 ----
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _refreshing ? null : _refreshModels,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                    icon: _refreshing
                        ? SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(_refreshing ? '正在拉取…' : '刷新模型',
                        style: const TextStyle(fontSize: 13.5)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMain,
                      side: BorderSide(color: AppColors.divider),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                    icon: _testing
                        ? SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary))
                        : const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: const Text('测试连接', style: TextStyle(fontSize: 13.5)),
                  ),
                ),
              ],
            ),

            // ---- 刷新结果提示 ----
            if (_refreshNote != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _refreshOk ? AppColors.primarySoft : AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_refreshOk ? Icons.check_circle_rounded : Icons.info_rounded,
                        size: 15,
                        color: _refreshOk ? AppColors.primary : AppColors.accent),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(_refreshNote!,
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: _refreshOk ? AppColors.primary : AppColors.accent)),
                    ),
                  ],
                ),
              ),
            ],

            // ---- 四类能力选模型 ----
            const SizedBox(height: 14),
            Text('按用途挑模型',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSub)),
            const SizedBox(height: 2),
            Text('刷新出来的清单会按名字自动归类，归得不对就直接改。',
                style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            const SizedBox(height: 6),
            ...ModelKind.values.map(_kindRow),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openTryon,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(
                    _config.imageModel.isEmpty ? '进入试衣间（用后端默认模型）' : '进入试衣间',
                    style: const TextStyle(fontSize: 14)),
              ),
            ),

            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '🔒 地址、Key、模型选择只保存在这台设备上，不上传、不入库。'
                '试衣照片只从手机直发上面这个服务地址，不经过衣念服务器，不落任何云端存储。\n'
                '接口协议见交付包 docs/tryon-api.md。',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSub, height: 1.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// API Key 行：带「显示/隐藏」，避免在公共场合把 Key 露出来
  Widget _keyField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _keyCtrl,
        obscureText: !_keyVisible,
        style: TextStyle(fontSize: 13.5, color: AppColors.textMain),
        onChanged: (s) => _update(_config.copyWith(apiKey: s)),
        decoration: InputDecoration(
          isDense: true,
          labelText: 'API Key（可选）',
          hintText: '本地服务一般留空',
          hintStyle: TextStyle(fontSize: 12.5, color: AppColors.textHint),
          labelStyle: TextStyle(fontSize: 12.5, color: AppColors.textSub),
          filled: true,
          fillColor: AppColors.bg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          suffixIcon: IconButton(
            onPressed: () => setState(() => _keyVisible = !_keyVisible),
            icon: Icon(_keyVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                size: 18, color: AppColors.textHint),
            tooltip: _keyVisible ? '隐藏' : '显示',
          ),
        ),
      ),
    );
  }

  /// 单个能力（文本/图像/视频/TTS）的一行：图标 + 用途 + 下拉选模型
  Widget _kindRow(ModelKind kind) {
    final selected = _config.modelOf(kind);
    final picked = selected.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: picked ? AppColors.primarySoft : AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: picked ? AppColors.primary.withValues(alpha: 0.35) : AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(_kindIcon(kind), size: 18, color: picked ? AppColors.primary : AppColors.textHint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(kind.label,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: picked ? AppColors.primary : AppColors.textMain)),
                      if (picked) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text('已选',
                              style: TextStyle(fontSize: 9, color: Colors.white)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                      picked ? ModelHubService.guessKind(selected) == kind
                          ? '自动归类为${kind.label}'
                          : '你手动指定的'
                          : kind.usage,
                      style: TextStyle(fontSize: 10.5, color: AppColors.textHint)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _modelPicker(kind, selected),
          ],
        ),
      ),
    );
  }

  IconData _kindIcon(ModelKind k) {
    switch (k) {
      case ModelKind.text:
        return Icons.chat_bubble_outline_rounded;
      case ModelKind.image:
        return Icons.checkroom_rounded;
      case ModelKind.video:
        return Icons.movie_filter_rounded;
      case ModelKind.tts:
        return Icons.record_voice_over_rounded;
    }
  }

  /// 模型选择控件：优先用下拉（清单来自刷新结果），并始终提供「手动填」兜底
  Widget _modelPicker(ModelKind kind, String selected) {
    // 手动填的、或清单里已经不存在的（服务换版本了），都要能原样显示并允许改
    final inList = _models.contains(selected);
    final options = <String>[
      if (selected.isNotEmpty && !inList) selected,
      ..._models,
    ];

    return PopupMenuButton<String>(
      initialValue: inList ? selected : (options.isEmpty ? null : options.first),
      tooltip: '选择${kind.label}模型',
      onSelected: (v) async {
        if (v == '__manual__') {
          final typed = await _askManualModel(kind, selected);
          if (typed == null || typed.isEmpty) return;
          final next = _applyModel(_config, kind, typed);
          setState(() => _config = next);
          await ModelHubService.saveConfig(next);
          return;
        }
        final next = _applyModel(_config, kind, v);
        setState(() => _config = next);
        await ModelHubService.saveConfig(next);
      },
      itemBuilder: (ctx) => [
        ...options.map((m) {
          final rec = ModelHubService.guessKind(m) == kind;
          return PopupMenuItem(
            value: m,
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: Text(m,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: m == selected ? FontWeight.w600 : FontWeight.w400,
                          color: m == selected ? AppColors.primary : AppColors.textMain)),
                ),
                if (rec) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('推荐',
                        style: TextStyle(fontSize: 9, color: AppColors.accent)),
                  ),
                ],
              ],
            ),
          );
        }),
        if (options.isNotEmpty) const PopupMenuDivider(),
        // 兜底：不少自建服务不提供 /models，只能手填名字
        PopupMenuItem(
          value: '__manual__',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 15, color: AppColors.primary),
              SizedBox(width: 8),
              Text('手动填写模型名…',
                  style: TextStyle(fontSize: 12.5, color: AppColors.primary)),
            ],
          ),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected.isNotEmpty ? AppColors.primary : AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selected.isEmpty ? '未选择' : selected,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: selected.isNotEmpty ? AppColors.primary : AppColors.textHint),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded,
                size: 15,
                color: selected.isNotEmpty ? AppColors.primary : AppColors.textHint),
          ],
        ),
      ),
    );
  }

  /// 手动填模型名：自建服务常常不提供 /models 接口，这时只能靠用户手打
  Future<String?> _askManualModel(ModelKind kind, String current) async {
    final ctrl = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('手动填写${kind.label}模型名',
            style: TextStyle(fontSize: 16, color: AppColors.textMain)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${kind.usage}。照你服务端文档里的模型 id 填，比如 '
                '${_manualExample(kind)}',
                style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: TextStyle(fontSize: 13.5, color: AppColors.textMain),
              decoration: InputDecoration(
                isDense: true,
                hintText: _manualExample(kind),
                hintStyle: TextStyle(fontSize: 12, color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.bg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // 留空= 不启用这项能力；本来就没选时「清空」等价于取消
              if (current.isNotEmpty) {
                Navigator.pop(ctx, '');
              } else {
                Navigator.pop(ctx);
              }
            },
            child: Text('清空',
                style: TextStyle(fontSize: 13, color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TextStyle(fontSize: 13, color: AppColors.textSub)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            ),
            child: const Text('确定', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _manualExample(ModelKind k) {
    switch (k) {
      case ModelKind.text:
        return 'qwen2.5:7b / gpt-4o-mini';
      case ModelKind.image:
        return 'flux.1-dev / qwen-image';
      case ModelKind.video:
        return 'cogvideox-5b / sora-2';
      case ModelKind.tts:
        return 'cosyvoice-v2 / gpt-4o-mini-tts';
    }
  }

  Widget _field(TextEditingController ctrl, String label, String hint,
      {bool obscure = false, String? helper, required ValueChanged<String> onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl,
            obscureText: obscure,
            keyboardType: label.startsWith('服务地址') ? TextInputType.url : TextInputType.text,
            style: TextStyle(fontSize: 13.5, color: AppColors.textMain),
            onChanged: onChanged,
            decoration: InputDecoration(
              isDense: true,
              labelText: label,
              hintText: hint,
              hintStyle: TextStyle(fontSize: 12.5, color: AppColors.textHint),
              labelStyle: TextStyle(fontSize: 12.5, color: AppColors.textSub),
              filled: true,
              fillColor: AppColors.bg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(helper,
                  style: TextStyle(fontSize: 10.5, color: AppColors.textHint, height: 1.4)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _aboutCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('衣念',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.textMain)),
              const SizedBox(width: 8),
              Text('v${ApiClient.appVersion}',
                  style: TextStyle(fontSize: 12, color: AppColors.textSub)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ApiClient.useMock
                ? '当前为演示模式（内置示例数据），连接正式服务请使用打包时的 API_BASE_URL。'
                : '已连接 ${ApiClient.baseUrl}',
            style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        backgroundColor: AppColors.textMain,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }
}
