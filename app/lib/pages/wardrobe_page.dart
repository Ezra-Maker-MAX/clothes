// 衣橱页 —— 参考 lookie 衣橱主页形态：
// 统计标题 + 动态分类 tab + 网格/列表视图 + 排序 + 搜索 + 底部「添加单品」胶囊
// 第三阶段：真实模式从 /api/wardrobe 拉取真实单品；卡片点进详情页；
// 分类管理（增删改/拖拽排序）、搜索、价格展示一应俱全。
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/mock_data.dart';
import '../theme/app_colors.dart';
import '../widgets/category_manage_sheet.dart';
import '../widgets/item_form_sheet.dart';
import 'item_detail_page.dart';

enum _SortMode { newest, mostWorn, recentWorn }

class WardrobePage extends StatefulWidget {
  const WardrobePage({super.key});

  @override
  State<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<WardrobePage> {
  bool _loading = false;
  String? _errorDetail;
  bool _listView = false; // 网格 / 列表（参考竞品右上角切换）
  _SortMode _sort = _SortMode.newest;
  bool _searching = false; // 搜索态（头部搜索钮展开输入框）
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// 动态分类（内置 7 类 + 用户自建；管理弹层增删改后刷新）
  List<CategoryInfo> _cats = ApiClient.builtinCategories;
  int _selected = 0; // 0 = 全部，其余对应 _cats[_selected - 1]

  List<ItemInfo> _items = MockData.wardrobe; // 真实模式立即被 _load 替换
  bool get _real => !ApiClient.useMock;

  @override
  void initState() {
    super.initState();
    if (_real) _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cats = await ApiClient.getCategories();
      final items = await ApiClient.getWardrobe(categories: cats);
      if (mounted) {
        setState(() {
          _cats = cats;
          _items = items;
          _errorDetail = null;
          if (_selected > _cats.length) _selected = 0;
        });
      }
    } catch (e) {
      // 拉取失败保留 mock 兜底展示，不让页面空白
      if (mounted) setState(() => _errorDetail = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? get _selectedCatId => _selected == 0 ? null : _cats[_selected - 1].id;

  List<ItemInfo> get _filtered {
    // 真实模式按分类 id（动态分类），mock 演示数据只有 label，按名匹配
    Iterable<ItemInfo> list = _selected == 0
        ? _items
        : _items.where((i) => _real
            ? i.categoryId == _selectedCatId
            : i.categoryLabel == _cats[_selected - 1].name);
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((i) =>
          i.name.toLowerCase().contains(q) ||
          (i.brand ?? '').toLowerCase().contains(q) ||
          (i.colorName ?? '').contains(_query));
    }
    final result = list.toList();
    switch (_sort) {
      case _SortMode.newest:
        break; // 服务端默认 created_at DESC（最近添加在前）
      case _SortMode.mostWorn:
        result.sort((a, b) => b.wearCount.compareTo(a.wearCount));
      case _SortMode.recentWorn:
        result.sort((a, b) {
          final av = a.lastWornAt ?? '';
          final bv = b.lastWornAt ?? '';
          return bv.compareTo(av); // null（''）自然沉底
        });
    }
    return result;
  }

  int _count(String? catId) =>
      catId == null ? _items.length : _items.where((i) => i.categoryId == catId).length;

  int get _neverWorn => _items.where((i) => i.lastWornAt == null).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        if (_searching) _searchBar(),
        _categoryTabs(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _listView
                  ? _list()
                  : _grid(),
        ),
        _addButton(),
      ],
    );
  }

  // ---- 头部：大标题 + 统计 + 搜索/视图排序/添加 工具钮 ----
  Widget _header() {
    final statText = _real
        ? '${_items.length} 件单品 · 其中 $_neverWorn 件还没上过身'
        : '47 件单品 · 其中 9 件还没上过身';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
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
            tooltip: '搜索',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchCtrl.clear();
                _query = '';
              }
            }),
            icon: Icon(_searching ? Icons.search_off_rounded : Icons.search_rounded,
                color: AppColors.textMain),
          ),
          PopupMenuButton<String>(
            tooltip: '视图与排序',
            icon: const Icon(Icons.tune_rounded, color: AppColors.textMain),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (v) {
              if (v == 'manageCats') {
                _openCategoryManager();
                return;
              }
              setState(() {
                switch (v) {
                  case 'grid':
                    _listView = false;
                  case 'list':
                    _listView = true;
                  case 'newest':
                    _sort = _SortMode.newest;
                  case 'mostWorn':
                    _sort = _SortMode.mostWorn;
                  case 'recentWorn':
                    _sort = _SortMode.recentWorn;
                }
              });
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'grid', child: _MenuRow(Icons.grid_view_rounded, '网格视图')),
              const PopupMenuItem(value: 'list', child: _MenuRow(Icons.view_list_rounded, '列表视图')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'newest', child: _MenuRow(Icons.schedule_rounded, '按最近添加')),
              const PopupMenuItem(value: 'mostWorn', child: _MenuRow(Icons.local_fire_department_rounded, '按最常穿')),
              const PopupMenuItem(value: 'recentWorn', child: _MenuRow(Icons.history_rounded, '按最近穿着')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'manageCats', child: _MenuRow(Icons.category_rounded, '管理分类')),
            ],
          ),
          IconButton(
            onPressed: _openAddSheet,
            icon: const Icon(Icons.add_rounded, color: AppColors.textMain),
          ),
        ],
      ),
    );
  }

  // ---- 搜索条 ----
  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        onChanged: (v) => setState(() => _query = v.trim()),
        style: const TextStyle(fontSize: 14, color: AppColors.textMain),
        decoration: InputDecoration(
          hintText: '搜名称 / 品牌 / 颜色',
          hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textHint),
          isDense: true,
          filled: true,
          fillColor: AppColors.card,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  // ---- 动态分类 tab：横向滚动 + 计数，选中莫兰迪紫胶囊 ----
  Widget _categoryTabs() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        itemCount: _cats.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final selected = i == _selected;
          final label = i == 0 ? '全部' : _cats[i - 1].name;
          final count = i == 0 ? _count(null) : _count(_cats[i - 1].id);
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
                '$label ($count)',
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

  // ---- 网格视图：单品卡（有图显示图）+ 末尾虚线「添加」格 ----
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
        return GestureDetector(
          onTap: () => _openDetail(item),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppColors.softShadow,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(14)),
                    child: SizedBox(
                      width: double.infinity,
                      child: _itemVisual(item, emojiSize: 42),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                  child: Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                ),
                Text('${item.categoryLabel} · ${item.colorName ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 单品视觉：有图用网络图（加载失败回退 emoji），无图用 emoji
  Widget _itemVisual(ItemInfo item, {double emojiSize = 42}) {
    if (item.imageUrl != null && item.imageUrl!.startsWith('http')) {
      return Image.network(
        item.imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
            child: Text(item.emoji, style: TextStyle(fontSize: emojiSize, height: 1.15))),
      );
    }
    return Center(child: Text(item.emoji, style: TextStyle(fontSize: emojiSize, height: 1.15)));
  }

  // ---- 列表视图：行卡（缩略 + 名称/品牌/价格 + 穿着徽章） ----
  Widget _list() {
    final items = _filtered;
    if (items.isEmpty) return _emptyResult();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        return GestureDetector(
          onTap: () => _openDetail(item),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppColors.softShadow,
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: _itemVisual(item, emojiSize: 28),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                      const SizedBox(height: 3),
                      Text(
                        '${item.categoryLabel}${item.colorName == null ? '' : ' · ${item.colorName}'}${item.brand == null ? '' : ' · ${item.brand}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSub),
                      ),
                      if (item.price != null) ...[
                        const SizedBox(height: 2),
                        Text('¥${_priceText(item.price!)} · 单次 ${item.costPerWear}',
                            style: const TextStyle(fontSize: 10.5, color: AppColors.accent)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: item.lastWornAt == null ? AppColors.bg : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item.lastWornAt == null ? '没穿过' : '穿过 ${item.wearCount} 次',
                    style: TextStyle(
                        fontSize: 10.5,
                        color: item.lastWornAt == null ? AppColors.textHint : AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyResult() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text(_query.isEmpty ? '这个分类还没有单品，点右下角加一件' : '没找到「$_query」相关的单品',
              style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
        ],
      ),
    );
  }

  String _priceText(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

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

  /// 点进单品详情；详情内编辑/删除返回 true 时刷新列表
  Future<void> _openDetail(ItemInfo item) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ItemDetailPage(item: item)),
    );
    if (changed == true) _load();
  }

  /// 打开「添加单品」表单；保存成功后刷新列表 + toast
  Future<void> _openAddSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ItemFormSheet(),
    );
    if (saved == true) {
      _toast('已挂进衣橱，下次搭配就能翻它的牌');
      _load();
    }
  }

  /// 分类管理（拖拽排序/重命名/新建/删除），关闭后刷新
  Future<void> _openCategoryManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => CategoryManageSheet(categories: _cats),
    );
    _load();
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

/// 排序/视图菜单行
class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSub),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.textMain)),
      ],
    );
  }
}
