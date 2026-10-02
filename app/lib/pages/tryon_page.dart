// 试衣间 —— 虚拟试衣客户端（实验性）
//
// 流程：选人像（1~5 张）→ 选服装（衣橱单品 / 相册）→ [可选]姿势参考 + 身体数据
//      → 生成（直发用户自部署模型服务）→ 结果预览 / 分享保存
//
// 隐私红线：本页所有图片只经 TryonService 直发用户配置的地址，
// 不触碰衣念服务端与任何云存储；结果图仅存内存与本地临时目录。
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/tryon_service.dart';
import '../theme/app_colors.dart';

class TryonPage extends StatefulWidget {
  const TryonPage({super.key, this.presetGarment});

  /// 从单品详情页进入时预置这件衣服
  final ItemInfo? presetGarment;

  @override
  State<TryonPage> createState() => _TryonPageState();
}

class _TryonPageState extends State<TryonPage> {
  static const int _maxPerson = 5;

  TryonConfig _config = const TryonConfig();
  final List<Uint8List> _personImages = [];
  Uint8List? _garmentBytes;
  String _garmentLabel = '还没选';
  Uint8List? _poseBytes;
  bool _generating = false;
  String? _resultError;
  Uint8List? _result;

  // 身体数据（可选）
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _bustCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _hipsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _bustCtrl.dispose();
    _waistCtrl.dispose();
    _hipsCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final c = await TryonService.loadConfig();
    if (!mounted) return;
    setState(() => _config = c);
    final preset = widget.presetGarment;
    if (preset?.imageUrl != null && preset!.imageUrl!.startsWith('http')) {
      await _useGarmentFromUrl(preset.imageUrl!, preset.name);
    }
  }

  // ---- 图片获取 ----

  Future<void> _pickPerson() async {
    if (_personImages.length >= _maxPerson) {
      _snack('最多 $_maxPerson 张人像，删一张再加');
      return;
    }
    final file = await FilePicker.pickFile(type: FileType.image, compressionQuality: 70);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _personImages.add(bytes));
  }

  Future<void> _pickPose() async {
    final file = await FilePicker.pickFile(type: FileType.image, compressionQuality: 70);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _poseBytes = bytes);
  }

  /// 服装来源一：相册
  Future<void> _garmentFromGallery() async {
    final file = await FilePicker.pickFile(type: FileType.image, compressionQuality: 70);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _garmentBytes = bytes;
      _garmentLabel = file.name;
    });
  }

  /// 服装来源二：衣橱单品（网络图 → 下载到内存，不落盘不传云端）
  Future<void> _useGarmentFromUrl(String url, String name) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      if (!mounted) return;
      setState(() {
        _garmentBytes = r.bodyBytes;
        _garmentLabel = name;
      });
    } catch (e) {
      if (mounted) _snack('「$name」的图拉不下来，试试从相册选服装图');
    }
  }

  Future<void> _pickGarmentFromWardrobe() async {
    try {
      final items = await ApiClient.getWardrobe();
      if (!mounted) return;
      final picked = await showModalBottomSheet<ItemInfo>(
        context: context,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('换哪件上机身？',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textMain)),
              ),
              ...items.map((it) => ListTile(
                    leading: it.imageUrl != null && it.imageUrl!.startsWith('http')
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(it.imageUrl!,
                                width: 44, height: 44, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Text(it.emoji, style: const TextStyle(fontSize: 24))))
                        : Text(it.emoji, style: const TextStyle(fontSize: 24)),
                    title: Text(it.name,
                        style: const TextStyle(fontSize: 14, color: AppColors.textMain)),
                    subtitle: Text(it.imageUrl == null ? '暂无图片（可用相册图代替）' : it.categoryLabel,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textHint)),
                    onTap: () => Navigator.pop(ctx, it),
                  )),
            ],
          ),
        ),
      );
      if (picked == null) return;
      if (picked.imageUrl == null || !picked.imageUrl!.startsWith('http')) {
        _snack('「${picked.name}」还没有图片，先去补图或从相册选服装图');
        return;
      }
      await _useGarmentFromUrl(picked.imageUrl!, picked.name);
    } catch (e) {
      _snack('衣橱拉取失败：${e.toString().substring(0, e.toString().length.clamp(0, 60))}');
    }
  }

  // ---- 生成 ----

  TryonBodyData? _bodyFromForm() {
    double? parse(TextEditingController c) {
      final v = double.tryParse(c.text.trim());
      return (v == null || v <= 0) ? null : v;
    }

    final b = TryonBodyData(
      heightCm: parse(_heightCtrl),
      weightKg: parse(_weightCtrl),
      bust: parse(_bustCtrl),
      waist: parse(_waistCtrl),
      hips: parse(_hipsCtrl),
    );
    final empty = b.heightCm == null && b.weightKg == null && b.bust == null &&
        b.waist == null && b.hips == null;
    return empty ? null : b;
  }

  Future<void> _generate() async {
    if (!_config.isReady) {
      _snack('试衣服务还没配置好：去设置 → 虚拟试衣');
      return;
    }
    if (_personImages.isEmpty) {
      _snack('先加一张你的人像照');
      return;
    }
    if (_garmentBytes == null) {
      _snack('先选一件要试的服装');
      return;
    }
    setState(() {
      _generating = true;
      _resultError = null;
      _result = null;
    });
    try {
      final img = await TryonService().generate(
        c: _config,
        personImages: _personImages,
        garmentImage: _garmentBytes!,
        poseImage: _poseBytes,
        body: _bodyFromForm(),
      );
      if (mounted) setState(() => _result = img);
    } catch (e) {
      if (mounted) {
        setState(() => _resultError =
            e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 结果分享/保存：写本地临时文件 → 系统分享面板（不碰任何云）
  Future<void> _shareResult() async {
    final img = _result;
    if (img == null) return;
    try {
      final dir = Directory.systemTemp;
      final f = File(
          '${dir.path}/tryon_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(img);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(f.path)], text: '我的试穿效果'),
      );
    } catch (_) {
      _snack('分享没成功，长按图片截图保存也可以');
    }
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
        title: const Text('试衣间',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _section('人像照（1~$_maxPerson 张）',
              '站姿正面/侧面效果最好；照片只发往你自己的服务'),
          _personSection(),
          const SizedBox(height: 20),
          _section('要试的服装', '从衣橱选会自动拉图，也可以从相册选平铺图'),
          _garmentSection(),
          const SizedBox(height: 20),
          _section('姿势参考（可选）', '给模型一张目标姿势图，出图更稳'),
          _poseSection(),
          const SizedBox(height: 20),
          _bodySection(),
          const SizedBox(height: 24),
          _generateButton(),
          if (_generating) ...[
            const SizedBox(height: 18),
            _generatingCard(),
          ],
          if (_resultError != null) ...[
            const SizedBox(height: 18),
            _errorCard(),
          ],
          if (_result != null) ...[
            const SizedBox(height: 18),
            _section('试穿效果', '仅保存在本机，分享走系统面板'),
            _resultCard(),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, String tip) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textMain)),
          const SizedBox(height: 3),
          Text(tip, style: const TextStyle(fontSize: 11.5, color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _thumb(Uint8List bytes, {VoidCallback? onRemove}) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, width: 88, height: 118, fit: BoxFit.cover),
        ),
        if (onRemove != null)
          Positioned(
            right: 4, top: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close_rounded, size: 13, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _personSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          ..._personImages.asMap().entries.map((e) => _thumb(e.value,
              onRemove: () => setState(() => _personImages.removeAt(e.key)))),
          if (_personImages.length < _maxPerson)
            GestureDetector(
              onTap: _pickPerson,
              child: Container(
                width: 88, height: 118,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_rounded, size: 24, color: AppColors.primary),
                    SizedBox(height: 6),
                    Text('加人像', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _garmentSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 72, height: 96,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _garmentBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(_garmentBytes!, fit: BoxFit.cover))
                : const Icon(Icons.checkroom_rounded, color: AppColors.textHint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_garmentLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _miniBtn('从衣橱选', Icons.dry_cleaning_rounded, _pickGarmentFromWardrobe),
                    const SizedBox(width: 8),
                    _miniBtn('从相册选', Icons.photo_library_rounded, _garmentFromGallery),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _poseSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 60, height: 80,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _poseBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(_poseBytes!, fit: BoxFit.cover))
                : const Icon(Icons.accessibility_new_rounded, color: AppColors.textHint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(_poseBytes == null ? '未选择' : '已选（点击右侧可更换）',
                style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
          ),
          _miniBtn(_poseBytes == null ? '选姿势图' : '换一张',
              Icons.accessibility_new_rounded, _pickPose),
        ],
      ),
    );
  }

  Widget _bodySection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: const Text('身体数据（可选）',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textMain)),
          subtitle: const Text('身高体重三围，填了出图更贴身；不填也行',
              style: TextStyle(fontSize: 11.5, color: AppColors.textHint)),
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.textSub,
          children: [
            Row(children: [
              Expanded(child: _numField(_heightCtrl, '身高 cm', '165')),
              const SizedBox(width: 8),
              Expanded(child: _numField(_weightCtrl, '体重 kg', '52')),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _numField(_bustCtrl, '胸围 cm', '84')),
              const SizedBox(width: 8),
              Expanded(child: _numField(_waistCtrl, '腰围 cm', '66')),
              const SizedBox(width: 8),
              Expanded(child: _numField(_hipsCtrl, '臀围 cm', '90')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13.5, color: AppColors.textMain),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: AppColors.textHint),
        labelStyle: const TextStyle(fontSize: 11.5, color: AppColors.textSub),
        filled: true,
        fillColor: AppColors.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _miniBtn(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _generateButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _generating ? null : _generate,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        ),
        icon: _generating
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_awesome_rounded, size: 19),
        label: Text(_generating ? '正在出图…' : '生成试穿',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _generatingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary)),
          SizedBox(width: 14),
          Expanded(
            child: Text('本地模型正在画，30 秒到 3 分钟都正常，去倒杯水回来差不多刚好。',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSub, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Text(_resultError!,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFFB4654A), height: 1.55)),
    );
  }

  Widget _resultCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppColors.radius)),
            child: Image.memory(_result!, width: double.infinity, fit: BoxFit.cover),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _shareResult,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 17),
                label: const Text('保存 / 分享', style: TextStyle(fontSize: 13.5)),
              ),
            ),
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
