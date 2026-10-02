// 单品表单底部弹层 —— 添加 / 编辑 双模式（参考竞品编辑弹窗，莫兰迪紫风格）
// 名称 + 动态分类 chips + 颜色 + 品牌 + 价格 + 图片（可选，/api/upload 落 Blob）
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../theme/app_colors.dart';

class ItemFormSheet extends StatefulWidget {
  const ItemFormSheet({super.key, this.item});

  final ItemInfo? item; // null = 添加模式

  @override
  State<ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<ItemFormSheet> {
  late final bool _isEdit = widget.item != null;
  List<CategoryInfo> _cats = ApiClient.builtinCategories; // initState 异步替换为动态
  late String _catId;
  bool _saving = false;
  bool _uploading = false;
  String? _imageUrl; // 已上传的图片 URL（预览 + 提交）
  Uint8List? _previewBytes; // 本地预览（上传期间显示）

  late final _nameCtrl = TextEditingController(text: widget.item?.name ?? '');
  late final _colorCtrl = TextEditingController(text: widget.item?.colorName ?? '');
  late final _brandCtrl = TextEditingController(text: widget.item?.brand ?? '');
  late final _priceCtrl = TextEditingController(
      text: widget.item?.price == null ? '' : _trimPrice(widget.item!.price!));

  @override
  void initState() {
    super.initState();
    _catId = widget.item?.categoryId ?? 'tops';
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

  /// 选图 → 上传 Blob → 本地预览（compressionQuality 顺带压缩大图）
  Future<void> _pickImage() async {
    final file = await FilePicker.pickFile(
      type: FileType.image,
      compressionQuality: 70,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _previewBytes = bytes;
      _uploading = true;
    });
    try {
      final url = await ApiClient.uploadImage(
        bytes: bytes,
        filename: file.name,
        contentType: file.extension == 'png' ? 'image/png' : 'image/jpeg',
      );
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) {
        _previewBytes = null;
        var msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        if (msg.length > 80) msg = '${msg.substring(0, 80)}…';
        _snack('图片没传上：$msg');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
      if (_isEdit) {
        await ApiClient.updateWardrobeItem(
          id: widget.item!.id,
          name: name,
          categoryId: _catId,
          colorName: _colorCtrl.text.trim(),
          brand: _brandCtrl.text.trim(),
          price: price,
          imageUrl: _imageUrl,
        );
      } else {
        await ApiClient.addWardrobeItem(
          name: name,
          categoryId: _catId,
          colorName: _colorCtrl.text.trim(),
          brand: _brandCtrl.text.trim(),
          price: price,
          imageUrl: _imageUrl,
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
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSub),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // ---- 图片（点击选图，选完本地预览） ----
            GestureDetector(
              onTap: _uploading ? null : _pickImage,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 120,
                  width: double.infinity,
                  color: AppColors.bg,
                  child: _uploading
                      ? const Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                      : _previewBytes != null
                          ? Image.memory(_previewBytes!, fit: BoxFit.cover)
                          : _imageUrl != null
                              ? Image.network(_imageUrl!, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                      child: Text('📷 点击选一张图（可选）',
                                          style: TextStyle(fontSize: 12.5, color: AppColors.textHint))))
                              : const Center(
                                  child: Text('📷 点击选一张图（可选）',
                                      style: TextStyle(fontSize: 12.5, color: AppColors.textHint))),
                ),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _nameCtrl,
              autofocus: !_isEdit,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 15, color: AppColors.textMain),
              decoration: _inputDeco('单品名称，如「云朵白衬衫」'),
            ),
            const SizedBox(height: 14),
            const Text('分类',
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
                    style: const TextStyle(fontSize: 15, color: AppColors.textMain),
                    decoration: _inputDeco('颜色（可选）'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _brandCtrl,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 15, color: AppColors.textMain),
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
              style: const TextStyle(fontSize: 15, color: AppColors.textMain),
              decoration: _inputDeco('价格（可选），如 299').copyWith(
                prefixText: '¥ ',
                prefixStyle: const TextStyle(fontSize: 15, color: AppColors.textMain),
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
            const Center(
              child: Text('AI 美化/自动抠图在下一阶段上线；图片会存到云存储，换设备也在',
                  style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );
}
