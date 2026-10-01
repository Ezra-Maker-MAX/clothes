// 衣橱页 —— 参考 lookie 衣橱主页形态：
// 统计标题 + 计数分类 tab + 3 列网格 + 底部「添加单品」胶囊
import 'package:flutter/material.dart';

import '../models/models.dart';
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

  List<ItemInfo> get _filtered => _selected == 0
      ? MockData.wardrobe
      : MockData.wardrobe
          .where((i) => i.categoryLabel == _cats[_selected])
          .toList();

  int _count(String cat) => cat == '全部'
      ? MockData.wardrobe.length
      : MockData.wardrobe.where((i) => i.categoryLabel == cat).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        _categoryTabs(),
        Expanded(child: _grid()),
        _addButton(),
      ],
    );
  }

  // ---- 头部：大标题 + 统计（参考 lookie「共450件衣服 / 查看衣橱统计」） ----
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('我的衣橱',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain)),
              SizedBox(height: 4),
              Text('47 件单品 · 其中 9 件还没上过身',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
            ],
          ),
          const Spacer(),
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

  /// 虚线「添加」占位格（对应后端 POST /api/wardrobe 入口）
  Widget _addTile() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.textHint, width: 1.2, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(14),
        color: Colors.transparent,
      ),
      child: const Center(
        child: Icon(Icons.add_rounded, size: 30, color: AppColors.textHint),
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
          onPressed: () {}, // 第三阶段：拍照/相册 → /api/upload → 抠图 → 落库
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
}
