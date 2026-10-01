// 底部数据卡片：三张并排 —— 衣橱单品 / 本月搭配 / 未穿单品
// 数字使用高亮强调色（蜜桃橙），严格按视觉规范
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';

class StatsRow extends StatelessWidget {
  const StatsRow({super.key, required this.stats});

  final HomeStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _card('衣橱单品', stats.wardrobeItems, Icons.checkroom_rounded),
        const SizedBox(width: 10),
        _card('本月搭配', stats.monthOutfits, Icons.auto_awesome_rounded),
        const SizedBox(width: 10),
        _card('未穿单品', stats.neverWorn, Icons.inventory_2_outlined),
      ],
    );
  }

  Widget _card(String label, int value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppColors.radius),
          boxShadow: AppColors.softShadow,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(label,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
              ],
            ),
            const SizedBox(height: 6),
            // 统计数字：蜜桃橙高亮
            Text('$value',
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                    height: 1.1)),
          ],
        ),
      ),
    );
  }
}
