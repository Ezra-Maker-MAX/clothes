// 今日推荐穿搭卡片：标题栏 + 场景标签 · 三图横排 · 匹配理由 · 双按钮
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';
import 'item_image.dart';

class RecommendCard extends StatelessWidget {
  const RecommendCard({
    super.key,
    required this.outfit,
    required this.onSwap,
    required this.onAccept,
    required this.swapping,
  });

  final OutfitRecommendation outfit;
  final VoidCallback onSwap;
  final VoidCallback onAccept;
  final bool swapping; // 「换一套」加载态

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- 标题栏：标题 + 场景标签 ----
          Row(
            children: [
              Text('今日推荐穿搭',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMain)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  outfit.occasionLabel,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ---- 三张单品图横排：上衣 / 裤装 / 鞋子 ----
          Row(
            children: [
              for (final (i, item) in outfit.items.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: ItemImage(item: item)),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // ---- 妆容推荐（一行小字） ----
          Row(
            children: [
              Icon(Icons.face_retouching_natural_rounded,
                  size: 14, color: AppColors.accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '妆容：${outfit.makeup}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSub),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ---- 匹配理由（情绪价值文案） ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              outfit.reason,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textMain, height: 1.55),
            ),
          ),
          const SizedBox(height: 16),

          // ---- 操作按钮：白底描边「换一套」 + 紫色主按钮「就穿这套」 ----
          Row(
            children: [
              // 次按钮：白底描边
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: swapping ? null : onSwap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary, width: 1.2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: swapping
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.autorenew_rounded, size: 17),
                  label: const Text('换一套',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              // 主按钮：莫兰迪紫
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('就穿这套',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
