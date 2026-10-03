// 衣橱页 —— 参考 lookie 衣橱主页形态：
// 统计标题 + 动态分类 tab + 网格/列表视图 + 排序 + 搜索 + 底部「添加单品」胶囊
// 第三阶段：真实模式从 /api/wardrobe 拉取真实单品；卡片点进详情页；
// 分类管理（增删改/拖拽排序）、搜索、价格展示一应俱全。
// P0/P1：置顶优先（详情页 pin 联动）、按颜色排序、离屏海报分享。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/mock_data.dart';
import '../theme/app_colors.dart';
import '../widgets/category_manage_sheet.dart';
import '../widgets/item_form_sheet.dart';
import 'item_detail_page.dart';

enum _SortMode { newest, mostWorn, recentWorn, byColor }

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

  // ---- 海报分享（P1）：离屏渲染 → RepaintBoundary 截图 → 系统分享 ----
  final GlobalKey _posterKey = GlobalKey();
  bool _posterReady = false;
  List<ItemInfo> _posterItems = const [];

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
    // 各排序均为「置顶优先」：pinned 在前，其余按所选键
    int pinCmp(ItemInfo a, ItemInfo b) =>
        (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
    switch (_sort) {
      case _SortMode.newest:
        result.sort(pinCmp); // 次级键保持现有相对顺序（服务端 created_at DESC）
      case _SortMode.mostWorn:
        result.sort((a, b) {
          final c = pinCmp(a, b);
          return c != 0 ? c : b.wearCount.compareTo(a.wearCount);
        });
      case _SortMode.recentWorn:
        result.sort((a, b) {
          final c = pinCmp(a, b);
          if (c != 0) return c;
          return (b.lastWornAt ?? '').compareTo(a.lastWornAt ?? '');
        });
      case _SortMode.byColor:
        result.sort((a, b) {
          final c = pinCmp(a, b);
          if (c != 0) return c;
          // 颜色名排序（无颜色沉底），同色按名称
          final av = a.colorName, bv = b.colorName;
          if (av == null && bv == null) return a.name.compareTo(b.name);
          if (av == null) return 1;
          if (bv == null) return -1;
          final c2 = av.compareTo(bv);
          return c2 != 0 ? c2 : a.name.compareTo(b.name);
        });
    }
    return result;
  }

  int _count(String? catId) =>
      catId == null ? _items.length : _items.where((i) => i.categoryId == catId).length;

  int get _neverWorn => _items.where((i) => i.lastWornAt == null).length;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            if (_searching) _searchBar(),
            _categoryTabs(),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _listView
                      ? _list()
                      : _grid(),
            ),
            _addButton(),
          ],
        ),
        // 离屏海报：移出可视区但保持渲染，截图后即隐藏
        if (_posterReady)
          Positioned(left: -2000, top: 0, child: RepaintBoundary(key: _posterKey, child: _posterWidget())),
      ],
    );
  }

  /// 生成衣橱海报（前 9 件单品九宫格）→ 系统分享面板，本地出图不落云端
  Future<void> _sharePoster() async {
    final withImg = _filtered
        .where((i) => i.imageUrl != null && i.imageUrl!.startsWith('http'))
        .toList();
    final noImg = _filtered
        .where((i) => !(i.imageUrl != null && i.imageUrl!.startsWith('http')))
        .toList();
    final picks = [...withImg, ...noImg].take(9).toList();
    if (picks.isEmpty) {
      _toast('衣橱还是空的，先加几件再晒');
      return;
    }
    setState(() {
      _posterItems = picks;
      _posterReady = true;
    });
    try {
      await WidgetsBinding.instance.endOfFrame; // 等离屏海报完成一帧渲染
      final boundary =
          _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('海报没渲染出来');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('截图失败');
      final data = Uint8List.view(bytes.buffer);
      final f = File(
          '${Directory.systemTemp.path}/wardrobe_poster_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(data);
      await SharePlus.instance
          .share(ShareParams(files: [XFile(f.path)], text: '我的衣橱 · 来自「衣念」'));
    } catch (e) {
      _toast('海报没生成出来：${e.toString().substring(0, e.toString().length.clamp(0, 60))}');
    } finally {
      if (mounted) setState(() => _posterReady = false);
    }
  }

  /// 海报本体：紫渐变头 + 九宫格 + 署名（固定 340 宽，3x pixelRatio 出高清图）
  Widget _posterWidget() {
    final now = DateTime.now();
    return Container(
      width: 340,
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF9C87C9), AppColors.primary],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('我的衣橱',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  '${now.year}年${now.month}月${now.day}日 · ${_items.length} 件单品 · 穿搭日记第 ${now.month} 月',
                  style: TextStyle(
                      fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.75,
              children: [for (final it in _posterItems) _posterCell(it)],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 14),
            child: Text('衣念 · AI 穿搭助手',
                style: TextStyle(fontSize: 10.5, color: AppColors.textHint)),
          ),
        ],
      ),
    );
  }

  Widget _posterCell(ItemInfo it) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: AppColors.bg,
        alignment: Alignment.center,
        child: it.imageUrl != null && it.imageUrl!.startsWith('http')
            ? Image.network(
                it.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) =>
                    Text(it.emoji, style: const TextStyle(fontSize: 30)),
              )
            : Text(it.emoji, style: const TextStyle(fontSize: 30)),
      ),
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
                Text('我的衣橱',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                const SizedBox(height: 4),
                Text(statText,
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
                if (_errorDetail != null) ...[
                  const SizedBox(height: 2),
                  Text('数据加载失败，以下为演示数据：$_errorDetail',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: AppColors.textHint)),
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
            icon: Icon(Icons.tune_rounded, color: AppColors.textMain),
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
                  case 'byColor':
                    _sort = _SortMode.byColor;
                  case 'sharePoster':
                    _sharePoster();
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
              const PopupMenuItem(value: 'byColor', child: _MenuRow(Icons.palette_rounded, '按颜色')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'sharePoster', child: _MenuRow(Icons.ios_share_rounded, '分享衣橱海报')),
              const PopupMenuItem(value: 'manageCats', child: _MenuRow(Icons.category_rounded, '管理分类')),
            ],
          ),
          IconButton(
            onPressed: _openAddSheet,
            icon: Icon(Icons.add_rounded, color: AppColors.textMain),
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
        style: TextStyle(fontSize: 14, color: AppColors.textMain),
        decoration: InputDecoration(
          hintText: '搜名称 / 品牌 / 颜色',
          hintStyle: TextStyle(fontSize: 13, color: AppColors.textHint),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.textHint),
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
          child: Stack(
            children: [
              Container(
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
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                    ),
                    Text('${item.categoryLabel} · ${item.colorName ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: AppColors.textSub)),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              if (item.pinned)
                Positioned(
                  left: 6, top: 6,
                  child: Icon(Icons.push_pin_rounded, size: 14, color: AppColors.accent),
                ),
            ],
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
                      Row(
                        children: [
                          if (item.pinned) ...[
                            Icon(Icons.push_pin_rounded, size: 12, color: AppColors.accent),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${item.categoryLabel}${item.colorName == null ? '' : ' · ${item.colorName}'}${item.brand == null ? '' : ' · ${item.brand}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: AppColors.textSub),
                      ),
                      if (item.price != null) ...[
                        const SizedBox(height: 2),
                        Text('¥${_priceText(item.price!)} · 单次 ${item.costPerWear}',
                            style: TextStyle(fontSize: 10.5, color: AppColors.accent)),
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
              style: TextStyle(fontSize: 13, color: AppColors.textSub)),
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
        child: Center(
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
  /// onSplitDone：「一整身照片自动拆分」入橱完成时的回调——
  /// 那条流程自己会 pop 掉本弹层，拿不到 showModalBottomSheet 的返回值，只能靠回调通知。
  Future<void> _openAddSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ItemFormSheet(onSplitDone: () {
        _toast('一整身拆好入橱了，去看看对不对');
        _load();
      }),
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
        Text(label, style: TextStyle(fontSize: 13.5, color: AppColors.textMain)),
      ],
    );
  }
}
