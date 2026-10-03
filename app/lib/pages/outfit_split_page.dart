// 穿搭拆分结果确认页 —— 「一整身照片 → N 件单品」的人工校正台
//
// 交互取舍（为什么不是「一键全自动」）：
//   模型认得准的时候全自动很爽，但认错时用户要一个个删，改动成本反而更高。
//   所以做成「模型先给草稿 → 用户勾选/改名/改分类 → 批量入库」：
//   快的场景是三秒勾完，难的场景有明确的修改入口，不至于只能全盘接受。
//
// 每个条目都提供：
//   - 复选框：不要的直接去掉（模型多报的比漏报的多，这是刻意的）
//   - 名称 / 分类 / 颜色：可就地改，模型猜错了改一下就好
//   - 缩略图：能裁出独立单品图就展示裁剪结果，裁不出显示原图并说明原因
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/model_hub_service.dart';
import '../services/outfit_cropper.dart';
import '../theme/app_colors.dart';

/// 一条待确认的衣物（可编辑）
class _Draft {
  _Draft({
    required this.detected,
    required this.nameCtrl,
    required this.colorCtrl,
    required this.categoryId,
    required this.selected,
  });

  final DetectedGarment detected;
  final TextEditingController nameCtrl;
  final TextEditingController colorCtrl;
  String categoryId;
  bool selected;
  /// 裁剪结果；null = 还没裁 / 裁失败用原图
  CropResult? crop;

  bool get hasImage => crop != null;
}

/// 入口：选一张一整身照片 → 识别 → 确认页 → 批量入橱
class OutfitSplitFlow {
  /// 从衣橱「添加单品」进入。
  /// [onDone] 在至少一件入橱成功后回调（用于让衣橱页刷新列表）——注意不是 pop 返回值：
  /// 弹层已被关闭，衣橱页的 await 拿不到结果，只能靠回调通知。
  static Future<void> start(
    BuildContext sheetContext, {
    required Uint8List image,
    required String filename,
    required String contentType,
    VoidCallback? onDone,
  }) async {
    // 关键：在关闭弹层**之前**抓住根导航器的 context。
    // 弹层一pop，sheetContext 就失效了，之后再拿它 showDialog / push 必崩。
    final rootNav = Navigator.of(sheetContext, rootNavigator: true);
    final navContext = rootNav.context;

    final hub = await ModelHubService.loadConfig();
    if (!sheetContext.mounted) return; // 弹层可能在等待期间已被关掉
    if (!hub.baseOk) {
      _toast(sheetContext, '先去设置 → 自部署模型，填好服务地址');
      return;
    }
    if (hub.textModel.isEmpty && hub.imageModel.isEmpty) {
      _toast(sheetContext, '还没选模型。去设置 → 自部署模型，挑一个能读图的多模态模型');
      return;
    }

    // 先关掉添加单品的弹层，避免两层 bottom sheet 叠着
    Navigator.of(sheetContext).pop();

    // 用根导航器的 context 弹进度窗（识别要几十秒，必须有明确反馈）
    showDialog<void>(
      context: navContext,
      barrierDismissible: false,
      builder: (_) => const _AnalyzingDialog(),
    );
    final result = await ModelHubService().analyzeOutfit(
      c: hub,
      image: image,
      mimeType: contentType,
    );
    if (navContext.mounted) Navigator.of(navContext, rootNavigator: true).pop();

    if (!navContext.mounted) return;
    if (!result.ok) {
      _toast(navContext, result.warning ?? '没认出衣物');
      return;
    }

    final saved = await Navigator.of(navContext, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => _SplitReviewPage(
          original: image,
          filename: filename,
          contentType: contentType,
          analysis: result,
        ),
      ),
    );
    if (saved == true) onDone?.call();
  }

  static void _toast(BuildContext context, String msg) {
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

/// 识别中的进度窗
class _AnalyzingDialog extends StatelessWidget {
  const _AnalyzingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  width: 26,
                  height: 26,
                  child:
                      CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary)),
              const SizedBox(height: 16),
              Text('正在读图拆分…',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
              const SizedBox(height: 6),
              Text('多模态模型要读一遍图，慢的话一两分钟',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textHint)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitReviewPage extends StatefulWidget {
  const _SplitReviewPage({
    required this.original,
    required this.filename,
    required this.contentType,
    required this.analysis,
  });

  final Uint8List original;
  final String filename;
  final String contentType;
  final OutfitAnalysis analysis;

  @override
  State<_SplitReviewPage> createState() => _SplitReviewPageState();
}

class _SplitReviewPageState extends State<_SplitReviewPage> {
  late List<_Draft> _drafts;
  late List<CategoryInfo> _cats;
  bool _saving = false;
  String? _banner;

  @override
  void initState() {
    super.initState();
    _banner = widget.analysis.warning;
    _cats = ApiClient.builtinCategories;
    _drafts = widget.analysis.garments.map(_makeDraft).toList();
    // 首屏先把裁剪算好，用户看到的就是最终图
    _precropAll();
    _loadCats();
  }

  /// 模型给的分类 id 与内置 id 可能不一致（模型爱用 dress/bag 单数），
  /// 这里做一次映射，找不到就落到「上衣」并让用户自己改。
  String _mapCategory(String hint) {
    if (hint.isEmpty) return 'tops';
    final h = hint.toLowerCase();
    const alias = {
      'dress': 'dresses',
      'bag': 'bags',
      'shoe': 'shoes',
      'top': 'tops',
      'bottom': 'bottoms',
      'outer': 'outerwear',
      'coat': 'outerwear',
      'jacket': 'outerwear',
      'accessory': 'accessories',
      'pants': 'bottoms',
      'skirt': 'bottoms',
    };
    final mapped = alias[h] ?? h;
    if (_cats.any((c) => c.id == mapped)) return mapped;
    return 'tops';
  }

  _Draft _makeDraft(DetectedGarment g) {
    final name =
        g.colorName.isNotEmpty && !g.name.startsWith(g.colorName)
            ? '${g.colorName}${g.name}'
            : g.name;
    return _Draft(
      detected: g,
      nameCtrl: TextEditingController(text: name),
      colorCtrl: TextEditingController(text: g.colorName),
      categoryId: _mapCategory(g.categoryHint),
      selected: true, // 默认全选：多数图确实有多件，删比选省事
    );
  }

  Future<void> _loadCats() async {
    final cats = await ApiClient.getCategories();
    if (!mounted || cats.isEmpty) return;
    setState(() {
      _cats = cats;
      for (final d in _drafts) {
        if (!cats.any((c) => c.id == d.categoryId)) d.categoryId = cats.first.id;
      }
    });
  }

  void _precropAll() {
    for (final d in _drafts) {
      final box = d.detected.box;
      if (box == null) continue;
      d.crop = OutfitCropper.crop(original: widget.original, box: box);
    }
  }

  int get _selectedCount => _drafts.where((d) => d.selected).length;

  /// 批量入库：逐件上传 → 写库。返回成功件数
  Future<void> _saveAll() async {
    final picked = _drafts.where((d) => d.selected).toList();
    if (picked.isEmpty) {
      OutfitSplitFlow._toast(context, '一件都没勾');
      return;
    }
    setState(() => _saving = true);
    var ok = 0;
    final failed = <String>[];
    for (var i = 0; i < picked.length; i++) {
      final d = picked[i];
      setState(() => _banner = '正在入库 ${i + 1}/${picked.length}…');
      final name = d.nameCtrl.text.trim();
      if (name.isEmpty) {
        failed.add('第${i + 1}件没名字');
        continue;
      }
      try {
        // 裁剪结果优先；裁不出就用原图
        final bytes = d.crop?.bytes ?? widget.original;
        final up = await ApiClient.uploadImage(
          bytes: bytes,
          filename: '${widget.filename.split('.').first}_$i.jpg',
          contentType: 'image/jpeg',
        );
        final url = up.cutoutUrl ?? up.url;
        if (url.isEmpty) {
          failed.add('$name 图没传上');
          continue;
        }
        await ApiClient.addWardrobeItem(
          name: name,
          categoryId: d.categoryId,
          colorName: d.colorCtrl.text.trim(),
          imageUrl: url,
        );
        ok++;
      } catch (e) {
        var msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        if (msg.length > 60) msg = '${msg.substring(0, 60)}…';
        failed.add('$name（$msg）');
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);

    if (ok == 0) {
      setState(() => _banner = '一件都没存进去：${failed.take(2).join('；')}');
      return;
    }
    OutfitSplitFlow._toast(context, failed.isEmpty
        ? '入橱 $ok 件，去衣橱看看'
        : '入橱 $ok 件，${failed.length} 件没成：${failed.first}');
    if (mounted) Navigator.pop(context, true);
  }

  /// 手动加一件（模型漏了的情况）
  void _addManual() {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('补一件',
            style: TextStyle(fontSize: 16, color: AppColors.textMain)),
        content: TextField(
          controller: c,
          autofocus: true,
          style: TextStyle(fontSize: 14, color: AppColors.textMain),
          decoration: InputDecoration(
            hintText: '如：米色风衣',
            hintStyle: TextStyle(fontSize: 13, color: AppColors.textHint),
            filled: true,
            fillColor: AppColors.bg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TextStyle(fontSize: 13, color: AppColors.textSub)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            ),
            child: const Text('添加', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    ).then((v) {
      if (v is String && v.isNotEmpty && mounted) {
        setState(() {
          _drafts.add(_Draft(
            detected: DetectedGarment(name: v, categoryHint: ''),
            nameCtrl: TextEditingController(text: v),
            colorCtrl: TextEditingController(),
            categoryId: 'tops',
            selected: true,
          ));
        });
      }
    });
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.nameCtrl.dispose();
      d.colorCtrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          icon: Icon(Icons.close_rounded, color: AppColors.textMain),
        ),
        title: Text('认出了 ${_drafts.length} 件',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                if (_banner != null) ...[
                  _bannerCard(_banner!),
                  const SizedBox(height: 12),
                ],
                Text('照你的习惯改一下，不想要的直接去掉',
                    style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                const SizedBox(height: 10),
                ...List.generate(_drafts.length, (i) => _card(i)),
                const SizedBox(height: 10),
                _addManualButton(),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _bannerCard(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_rounded, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                    fontSize: 11.5, color: AppColors.accent, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _card(int i) {
    final d = _drafts[i];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
        border: Border.all(
            color: d.selected ? AppColors.primary.withValues(alpha: 0.4) : AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 勾选
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: d.selected,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() => d.selected = v ?? false),
                ),
              ),
              const SizedBox(width: 8),
              // 缩略图
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 62,
                  height: 78,
                  child: Image.memory(d.crop?.bytes ?? widget.original,
                      fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              // 名称 + 颜色
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: d.nameCtrl,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMain),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '单品名',
                        hintStyle: TextStyle(fontSize: 13.5, color: AppColors.textHint),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: d.colorCtrl,
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSub),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '颜色（可选）',
                        hintStyle: TextStyle(fontSize: 12, color: AppColors.textHint),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _drafts.removeAt(i)),
                icon: Icon(Icons.delete_outline_rounded,
                    size: 19, color: AppColors.textHint),
                tooltip: '去掉这件',
              ),
            ],
          ),
          // 分类 chips
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _cats.map((c) {
                final on = c.id == d.categoryId;
                return GestureDetector(
                  onTap: () => setState(() => d.categoryId = c.id),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: on ? AppColors.primary : AppColors.bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: on ? AppColors.primary : AppColors.divider),
                    ),
                    child: Text(c.name,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                                on ? FontWeight.w600 : FontWeight.w400,
                            color: on ? Colors.white : AppColors.textSub)),
                  ),
                );
              }).toList(),
            ),
          ),
          if (d.crop != null && !d.crop!.ok && d.crop!.note != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 13, color: AppColors.textHint),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(d.crop!.note!,
                      style: TextStyle(
                          fontSize: 10.5, color: AppColors.textHint)),
                ),
              ],
            ),
          ],
          if (d.detected.box == null) ...[
            const SizedBox(height: 6),
            Text('模型没给位置，这件用整图',
                style: TextStyle(fontSize: 10.5, color: AppColors.textHint)),
          ],
        ],
      ),
    );
  }

  Widget _addManualButton() {
    return OutlinedButton.icon(
      onPressed: _saving ? null : _addManual,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: BorderSide(color: AppColors.divider),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('模型漏了一件？手动补',
          style: TextStyle(fontSize: 13)),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF715F9B).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('$_selectedCount 件待入橱',
                style: TextStyle(fontSize: 13, color: AppColors.textSub)),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _saveAll,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_saving ? '入库中…' : '全部挂进衣橱',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
