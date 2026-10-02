// 设置页 —— 目前承载「虚拟试衣 · 自部署模型」配置区 + 关于
//
// 设计原则：
// - 试衣服务是用户自己的模型端点，配置只存手机本地（SharedPreferences），不上传；
// - 试衣图片只从手机直发该地址，不经过衣念服务端 —— 云端零留存（详见 tryon_service.dart 头注释）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/tryon_page.dart';
import '../services/api_client.dart';
import '../services/tryon_service.dart';
import '../theme/app_colors.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  TryonConfig _config = const TryonConfig();
  bool _loaded = false;
  bool _testing = false;
  bool _importing = false;
  Timer? _saveDebounce;

  final _baseCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _orderCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _baseCtrl.dispose();
    _pathCtrl.dispose();
    _keyCtrl.dispose();
    _orderCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await TryonService.loadConfig();
    final city = await ApiClient.weatherCity();
    if (!mounted) return;
    setState(() {
      _config = c;
      _baseCtrl.text = c.baseUrl;
      _pathCtrl.text = c.path;
      _keyCtrl.text = c.apiKey;
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
  void _update(TryonConfig next) {
    setState(() => _config = next);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      TryonService.saveConfig(_config);
    });
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final err = await TryonService().testConnection(_config);
    if (!mounted) return;
    setState(() => _testing = false);
    _snack(err ?? '服务在线，可以开试 👌');
  }

  void _openTryon() {
    if (!_config.isReady) {
      _snack('先把服务地址填好并打开开关');
      return;
    }
    TryonService.saveConfig(_config); // 进试衣间前确保落盘
    Navigator.push(context, MaterialPageRoute(builder: (_) => const TryonPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textMain),
        ),
        title: const Text('设置',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        centerTitle: true,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                _sectionTitle('天气 · 常驻城市', '精准推荐'),
                _cityCard(),
                const SizedBox(height: 20),
                _sectionTitle('虚拟试衣 · 自部署模型', '实验性'),
                _tryonCard(),
                const SizedBox(height: 20),
                _sectionTitle('批量导入', '省事'),
                _importCard(),
                const SizedBox(height: 20),
                _sectionTitle('关于', null),
                _aboutCard(),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '你的衣橱数据与试衣配置都只属于你：'
                    '衣橱数据存放在你自己的数据库，试衣照片只发往你自己配置的模型服务。',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textHint, height: 1.6),
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
              const Icon(Icons.playlist_add_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('从订单文本导入',
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textMain)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('把购物 App 订单里的商品名一行一个粘进来，自动识别分类与价格后批量入橱。',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSub, height: 1.5)),
          const SizedBox(height: 10),
          TextField(
            controller: _orderCtrl,
            maxLines: 5,
            style: const TextStyle(fontSize: 13, color: AppColors.textMain),
            decoration: InputDecoration(
              hintText: '云朵白衬衫 299\n高腰直筒牛仔裤 459\n裸色平底穆勒鞋 368',
              hintStyle: const TextStyle(fontSize: 12, color: AppColors.textHint),
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
              style: const TextStyle(
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
                  style: const TextStyle(fontSize: 10.5, color: AppColors.accent)),
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
              const Icon(Icons.location_on_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('你所在的城市',
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textMain)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('留空 = 按当前网络自动定位（推荐，桌面和手机都生效）；'
              '填城市名则以你填的为准，出差/跨城时更准。',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSub, height: 1.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _cityCtrl,
            style: const TextStyle(fontSize: 13, color: AppColors.textMain),
            decoration: InputDecoration(
              hintText: '留空自动定位，或填：杭州 / Beijing',
              hintStyle: const TextStyle(fontSize: 12, color: AppColors.textHint),
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
                child: const Text('清空，自动定位',
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

  Widget _tryonCard() {
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
          // 开关行
          Row(
            children: [
              const Icon(Icons.checkroom_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('启用试衣间',
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain)),
              ),
              Switch(
                value: _config.enabled,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => _update(
                  TryonConfig(
                    enabled: v,
                    baseUrl: _baseCtrl.text,
                    path: _pathCtrl.text,
                    apiKey: _keyCtrl.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _field(_baseCtrl, '服务地址', 'http://192.168.1.5:8000',
              onChanged: (s) => _update(TryonConfig(
                  enabled: _config.enabled, baseUrl: s, path: _pathCtrl.text, apiKey: _keyCtrl.text))),
          _field(_pathCtrl, '接口路径', '/tryon',
              onChanged: (s) => _update(TryonConfig(
                  enabled: _config.enabled, baseUrl: _baseCtrl.text, path: s, apiKey: _keyCtrl.text))),
          _field(_keyCtrl, 'API Key（可选）', '留空则不发送',
              obscure: true,
              onChanged: (s) => _update(TryonConfig(
                  enabled: _config.enabled,
                  baseUrl: _baseCtrl.text,
                  path: _pathCtrl.text,
                  apiKey: s))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMain,
                    side: const BorderSide(color: AppColors.divider),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  ),
                  icon: _testing
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                      : const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: const Text('测试连接', style: TextStyle(fontSize: 13.5)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openTryon,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('进入试衣间', style: TextStyle(fontSize: 13.5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '🔒 试衣照片只从手机直发上面这个地址（你的自有模型服务），'
              '不经过衣念服务器，不落任何云端存储；本配置也只保存在手机本地。\n'
              '模型端如何搭建见交付包 docs/tryon-api.md。',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSub, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint,
      {bool obscure = false, required ValueChanged<String> onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: label == '服务地址' ? TextInputType.url : TextInputType.text,
        style: const TextStyle(fontSize: 13.5, color: AppColors.textMain),
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textHint),
          labelStyle: const TextStyle(fontSize: 12.5, color: AppColors.textSub),
          filled: true,
          fillColor: AppColors.bg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
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
              const Text('衣念',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.textMain)),
              const SizedBox(width: 8),
              Text('v${ApiClient.appVersion}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ApiClient.useMock
                ? '当前为演示模式（内置示例数据），连接正式服务请使用打包时的 API_BASE_URL。'
                : '已连接 ${ApiClient.baseUrl}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5),
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
