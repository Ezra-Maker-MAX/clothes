// 衣橱页 —— 参考 lookie 衣橱主页形态：
// 统计标题 + 计数分类 tab + 3 列网格 + 底部「添加单品」胶囊
// 第三阶段：真实模式从 /api/wardrobe 拉取真实单品；「添加单品」弹表单
// 手动录入（POST /api/wardrobe），拍照/抠图上传属后续阶段。
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/mock_data.dart';
import '../theme/app_colors.dart';

class WardrobePage extends StatefulWidget {
  const WardrobePage({super.key});

  @override
  State<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<WardrobePage> {
  /// 展示顺序即 tab 顺序
  static const _cats = ['全部', '上衣', '裤装', '裙装', '外套', '鞋子', '配饰'];
  int _selected = 0;
  bool _loading = false;
  String? _errorDetail; // 真实异常（加载失败时小字展示，便于远程诊断）

  List<ItemInfo> _items = MockData.wardrobe; // 真实模式立即被 _load 替换
  bool get _real => !ApiClient.useMock;

  @override
  void initState() {
    super.initState();
    if (_real) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await ApiClient.getWardrobe();
      if (mounted) {
        setState(() {
          _items = items;
          _errorDetail = null;
        });
      }
    } catch (e) {
      // 拉取失败保留 mock 兜底展示，不让页面空白
      if (mounted) setState(() => _errorDetail = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ItemInfo> get _filtered => _selected == 0
      ? _items
      : _items.where((i) => i.categoryLabel == _cats[_selected]).toList();

  int _count(String cat) => cat == '全部'
      ? _items.length
      : _items.where((i) => i.categoryLabel == cat).length;

  int get _neverWorn => _items.where((i) => i.lastWornAt == null).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        _categoryTabs(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _grid(),
        ),
        _addButton(),
      ],
    );
  }

  // ---- 头部：大标题 + 统计（参考 lookie「共450件衣服 / 查看衣橱统计」） ----
  Widget _header() {
    final statText = _real
        ? '${_items.length} 件单品 · 其中 $_neverWorn 件还没上过身'
        : '47 件单品 · 其中 9 件还没上过身';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('我的衣橱',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                const SizedBox(height: 4),
                Text(statText,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSub)),
                if (_errorDetail != null) ...[
                  const SizedBox(height: 2),
                  Text('数据加载失败，以下为演示数据：$_errorDetail',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textHint)),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search_rounded, color: AppColors.textMain),
          ),
        ],
      ),
    );
  }

  // ---- 分类 tab：横向滚动 + 计数，选中莫兰迪紫胶囊 ----
  Widget _categoryTabs() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        itemCount: _cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final selected = i == _selected;
          return GestureDetector(
            onTap: () => setState(() => _selected = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(16),
                boxShadow: selected ? null : AppColors.softShadow,
              ),
              child: Text(
                '${_cats[i]} (${_count(_cats[i])})',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.textSub,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- 3 列网格：单品卡 + 末尾虚线「添加」格 ----
  Widget _grid() {
    final items = _filtered;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: items.length + 1,
      itemBuilder: (_, i) {
        if (i == items.length) return _addTile();
        final item = items[i];
        return Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.softShadow,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(item.emoji, style: const TextStyle(fontSize: 42, height: 1.15)),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMain)),
              ),
              Text('${item.categoryLabel} · ${item.colorName ?? ''}',
                  style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
            ],
          ),
        );
      },
    );
  }

  /// 虚线「添加」占位格（POST /api/wardrobe 入口，与底部主按钮同表单）
  Widget _addTile() {
    return GestureDetector(
      onTap: _openAddSheet,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.textHint, width: 1.2, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(14),
          color: Colors.transparent,
        ),
        child: const Center(
          child: Icon(Icons.add_rounded, size: 30, color: AppColors.textHint),
        ),
      ),
    );
  }

  // ---- 底部主按钮：紫色胶囊「添加单品」 ----
  Widget _addButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _openAddSheet,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('添加单品',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  /// 打开「添加单品」表单；保存成功后刷新列表 + toast
  Future<void> _openAddSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AddItemSheet(),
    );
    if (saved == true) {
      _toast('已挂进衣橱，下次搭配就能翻它的牌');
      _load();
    }
  }

  void _toast(String msg) {
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

/// 「添加单品」底部表单：名称 + 分类 + 颜色（可选）→ POST /api/wardrobe
class AddItemSheet extends StatefulWidget {
  const AddItemSheet({super.key});

  @override
  State<AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<AddItemSheet> {
  static const _catOptions = ['上衣', '裤装', '裙装', '外套', '鞋子', '配饰'];
  String _cat = '上衣';
  bool _saving = false;
  final _nameCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('先给它起个名字吧，比如「云朵白衬衫」');
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.addWardrobeItem(
        name: name,
        categoryLabel: _cat,
        colorName: _colorCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        var msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        if (msg.length > 80) msg = '${msg.substring(0, 80)}…';
        _snack('没存进去：$msg');
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
                const Text('添加单品',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSub),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
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
                for (final c in _catOptions)
                  ChoiceChip(
                    label: Text(c),
                    selected: _cat == c,
                    onSelected: (_) => setState(() => _cat = c),
                    selectedColor: AppColors.primary,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: _cat == c ? FontWeight.bold : FontWeight.w500,
                      color: _cat == c ? Colors.white : AppColors.textSub,
                    ),
                    backgroundColor: AppColors.bg,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(
                        color: _cat == c ? AppColors.primary : AppColors.divider),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _colorCtrl,
              style: const TextStyle(fontSize: 15, color: AppColors.textMain),
              decoration: _inputDeco('颜色（可选），如「雾霾蓝」'),
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
                    : const Text('挂进衣橱',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text('拍照上传和自动抠图在下一阶段上线，先记名字就能参与搭配',
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
