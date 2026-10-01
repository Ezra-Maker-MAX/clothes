// 底部导航栏：首页 · 衣橱 · 搭配（带星标）· 历史
// 选中态：莫兰迪紫；「搭配」tab 右上角蜜桃色小星点缀
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class NavBar extends StatelessWidget {
  const NavBar({super.key, required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const _items = ['首页', '衣橱', '搭配', '历史'];
  static const _icons = [
    Icons.home_rounded,
    Icons.checkroom_rounded,
    Icons.auto_awesome_rounded,
    Icons.history_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF715F9B).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Row(
            children: [
              for (final (i, label) in _items.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(child: _item(i, label)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int i, String label) {
    final selected = i == index;
    final color = selected ? AppColors.primary : AppColors.textHint;

    Widget icon = Icon(_icons[i], size: 24, color: color);
    // 「搭配」tab 的星标点缀
    if (i == 2) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            right: -5,
            top: -3,
            child: Icon(
              selected ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 11,
              color: selected ? AppColors.accent : AppColors.textHint,
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: () => onTap(i),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
