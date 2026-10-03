// 单品表单底部弹层 —— 添加 / 编辑 双模式（参考竞品编辑弹窗，莫兰迪紫风格）
// 名称 + 动态分类 chips + 颜色 + 品牌 + 价格 + 图片（可选，/api/upload 落 Blob）
//
// 「一整身照片」入口：加图区最右那张橙色卡片，点它会让多模态模型把全身照拆成
// 单件，逐件确认后批量入橱（见 outfit_split_page.dart）。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../pages/outfit_split_page.dart';
import '../services/api_client.dart';
import '../services/image_service.dart';
import '../theme/app_colors.dart';

class ItemFormSheet extends StatefulWidget {
  const ItemFormSheet({super.key, this.item, this.onSplitDone});

  final ItemInfo? item; // null = 添加模式

  /// 「一整身拆分」成功入橱后的回调（用于让衣橱页刷新列表）。
  /// 必须是回调而非返回值：拆分流程第一步就会 pop 掉本弹层。
  final VoidCallback? onSplitDone;

  @override
  State<ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<ItemFormSheet> {
  static const int _maxImages = 5;

  late final bool _isEdit = widget.item != null;
  List<CategoryInfo> _cats = ApiClient.builtinCategories; // initState 异步替换为动态
  late String _catId;
  bool _saving = false;
  bool _uploading = false;
  bool _outfitMode = false; // 刚挑了「一整身」拆分原图
  List<String> _imageUrls = []; // 已上传的图片 URL 列表（第一张即主图）
  Uint8List? _previewBytes; // 本次上传中的本地预览

  late final _nameCtrl = TextEditingController(text: widget.item?.name ?? '');
  late final _colorCtrl = TextEditingController(text: widget.item?.colorName ?? '');
  late final _brandCtrl = TextEditingController(text: widget.item?.brand ?? '');
  late final _priceCtrl = TextEditingController(
      text: widget.item?.price == null ? '' : _trimPrice(widget.item!.price!));

  @override
  void initState() {
    super.initState();
    _catId = widget.item?.categoryId ?? 'tops';
    // 多图回显：旧数据只有单图也进列表首位
    final it = widget.item;
    if (it != null) {
      _imageUrls = it.imageUrls.isNotEmpty
          ? List.of(it.imageUrls)
          : (it.imageUrl != null && it.imageUrl!.isNotEmpty ? [it.imageUrl!] : []);
    }
    _loadCategories();
  }

  static String _trimPrice(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _loadCategories() async {
    final cats = await ApiClient.getCategories();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      if (!cats.any((c) => c.id == _catId) && cats.isNotEmpty) _catId = cats.first.id;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _colorCtrl.dispose();
    _brandCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  /// 选图 → 压缩（强制压到 3MB 安全线，规避 413）→ 上传 Blob → 加入多图列表
  /// 服务端若配置了 AI 抠图，cutoutUrl（去背 PNG）优先作为主图
  Future<void> _pickImage() async {
    if (_imageUrls.length >= _maxImages) {
      _snack('最多 $_maxImages 张图，删一张再加');
      return;
    }
    // 先亮 loading：大图（PNG/高像素照片）压缩要 1~3 秒，别让用户干等
    setState(() => _uploading = true);
    PickedImage? picked;
    try {
      picked = await pickImage(label: '图片');
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        _snack(e.toString().replaceFirst(RegExp(r'^Bad state:\s*'), ''));
      }
      return;
    }
    if (picked == null) {
      if (mounted) setState(() => _uploading = false);
      return; // 用户取消
    }
    setState(() => _previewBytes = picked!.bytes);
    try {
      final r = await ApiClient.uploadImage(
        bytes: picked.bytes,
        filename: picked.filename,
        contentType: picked.contentType,
      );
      final finalUrl = r.cutoutUrl ?? r.url; // 去背图优先当主图
      if (mounted && finalUrl.isNotEmpty) {
        setState(() => _imageUrls.add(finalUrl));
      }
    } catch (e) {
      if (mounted) {
        var msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        if (msg.length > 80) msg = '${msg.substring(0, 80)}…';
        _snack('图片没传上：$msg');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 「一整身？自动拆开」：选图后交给多模态模型拆分，进入逐件确认页。
  /// 这条路不把原图传 Blob —— 它只是拆分依据，拆完各单品才各自上传。
  ///
  /// 注意本弹层在流程开始时就被 pop 了（避免两层 bottom sheet 叠加），
  /// 所以 [onSplitDone] 必须是外部注入的回调，弹层自己没法再上报结果。
  Future<void> _pickOutfitPhoto() async {
    setState(() => _uploading = true);
    PickedImage? picked;
    try {
      picked = await pickImage(label: '全身照', maxWidth: 1400, quality: 88);
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        _snack(e.toString().replaceFirst(RegExp(r'^Bad state:\s*'), ''));
      }
      return;
    }
    if (picked == null) {
      if (mounted) setState(() => _uploading = false);
      return;
    }
    if (!mounted) return; // 跨过 pickImage 的 async gap，context 可能已失效
    setState(() {
      _outfitMode = true;
      _previewBytes = picked!.bytes;
    });
    // 不再 await 本弹层状态：它马上就被关闭了
    unawaited(OutfitSplitFlow.start(
      context,
      image: picked.bytes,
      filename: picked.filename,
      contentType: picked.contentType,
      onDone: widget.onSplitDone,
    ));
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('先给它起个名字吧，比如「云朵白衬衫」');
      return;
    }
    if (_uploading) {
      _snack('图片还在传，等一下下');
      return;
    }
    setState(() => _saving = true);
    try {
      final price = double.tryParse(_priceCtrl.text.trim());
      // 主图 = 多图第一张；列表为空时传空串让服务端清掉旧主图
      final mainUrl = _imageUrls.isEmpty ? '' : _imageUrls.first;
      if (_isEdit) {
        await ApiClient.updateWardrobeItem(
          id: widget.item!.id,
          name: name,
          categoryId: _catId,
          colorName: _colorCtrl.text.trim(),
          brand: _brandCtrl.text.trim(),
          price: price,
          imageUrl: mainUrl,
          imageUrls: _imageUrls,
        );
      } else {
        await ApiClient.addWardrobeItem(
          name: name,
          categoryId: _catId,
          colorName: _colorCtrl.text.trim(),
          brand: _brandCtrl.text.trim(),
          price: price,
          imageUrl: _imageUrls.isEmpty ? null : _imageUrls.first,
          imageUrls: _imageUrls,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        var msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        if (msg.length > 80) msg = '${msg.substring(0, 80)}…';
        _snack('${_isEdit ? '没存上' : '没存进去'}：$msg');
      }
    }
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

  @override
  Widget build(BuildContext context) {
    // viewInsets：键盘弹起时表单跟着上移，不被遮挡
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_isEdit ? '编辑单品' : '添加单品',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: AppColors.textSub),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // ---- 多图（横滑缩略图 + 加图块；第一张即主图，支持 AI 去背） ----
            SizedBox(
              height: 120,
              child: _uploading && _previewBytes != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                          const SizedBox(height: 8),
                          Text('正在上传（含 AI 抠图，稍等）…',
                              style: TextStyle(fontSize: 11.5, color: AppColors.textHint)),
                        ],
                      ),
                    )
                  : ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < _imageUrls.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: SizedBox(
                                    width: 96, height: 120,
                                    child: Image.network(_imageUrls[i], fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                            color: AppColors.bg,
                                            alignment: Alignment.center,
                                            child: Text(i == 0 ? '主图' : '${i + 1}',
                                                style: TextStyle(
                                                    fontSize: 11.5, color: AppColors.textHint)))),
                                  ),
                                ),
                                if (i == 0)
                                  Positioned(
                                    left: 6, bottom: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('主图',
                                          style: TextStyle(fontSize: 9.5, color: Colors.white)),
                                    ),
                                  ),
                                Positioned(
                                  right: 4, top: 4,
                                  child: Material(
                                    color: Colors.black54,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => setState(() => _imageUrls.removeAt(i)),
                                      child: const Padding(
                                        padding: EdgeInsets.all(3),
                                        child: Icon(Icons.close_rounded, size: 13, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_imageUrls.length < _maxImages)
                          GestureDetector(
                            onTap: _uploading ? null : _pickImage,
                            child: Container(
                              width: 96, height: 120,
                              decoration: BoxDecoration(
                                color: AppColors.bg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo_rounded, size: 22, color: AppColors.primary),
                                  const SizedBox(height: 6),
                                  Text('加图 ${_imageUrls.length}/$_maxImages',
                                      style: TextStyle(fontSize: 10.5, color: AppColors.textHint)),
                                ],
                              ),
                            ),
                          ),
                        // 「一整身照片」入口：让多模态模型先拆成单件，用户再逐件校对
                        _isEdit
                            ? const SizedBox.shrink()
                            : GestureDetector(
                                onTap: _uploading ? null : _pickOutfitPhoto,
                                child: Container(
                                  width: 96, height: 120,
                                  decoration: BoxDecoration(
                                    color: AppColors.accentSoft,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: AppColors.accent.withValues(alpha: 0.45)),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.auto_awesome_rounded,
                                          size: 22, color: AppColors.accent),
                                      const SizedBox(height: 6),
                                      Text('一整身？',
                                          style: TextStyle(
                                              fontSize: 10.5,
                                              color: AppColors.accent,
                                              fontWeight: FontWeight.w600)),
                                      Text('自动拆开',
                                          style: TextStyle(
                                              fontSize: 10.5, color: AppColors.accent)),
                                    ],
                                  ),
                                ),
                              ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),

            // 「一整身」提示条：只在挑了这张图之后出现
            if (_outfitMode) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_rounded, size: 15, color: AppColors.accent),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text('这是拆分原图，不会作为单品保存。'
                          '拆完会开一个确认页，逐件改名分类后批量入橱。',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.accent, height: 1.45)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            TextField(
              controller: _nameCtrl,
              autofocus: !_isEdit,
              textInputAction: TextInputAction.next,
              style: TextStyle(fontSize: 15, color: AppColors.textMain),
              decoration: _inputDeco('单品名称，如「云朵白衬衫」'),
            ),
            const SizedBox(height: 14),
            Text('分类',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _cats)
                  ChoiceChip(
                    label: Text(c.name),
                    selected: _catId == c.id,
                    onSelected: (_) => setState(() => _catId = c.id),
                    selectedColor: AppColors.primary,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: _catId == c.id ? FontWeight.bold : FontWeight.w500,
                      color: _catId == c.id ? Colors.white : AppColors.textSub,
                    ),
                    backgroundColor: AppColors.bg,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(
                        color: _catId == c.id ? AppColors.primary : AppColors.divider),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _colorCtrl,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(fontSize: 15, color: AppColors.textMain),
                    decoration: _inputDeco('颜色（可选）'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _brandCtrl,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(fontSize: 15, color: AppColors.textMain),
                    decoration: _inputDeco('品牌（可选）'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              style: TextStyle(fontSize: 15, color: AppColors.textMain),
              decoration: _inputDeco('价格（可选），如 299').copyWith(
                prefixText: '¥ ',
                prefixStyle: TextStyle(fontSize: 15, color: AppColors.textMain),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEdit ? '保存修改' : '挂进衣橱',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('多图第一张即主图；配置 AI 抠图后自动去背。图片存到云存储，换设备也在',
                  style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13.5, color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );
}
