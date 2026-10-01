// 搭配页（星标 tab）—— 双列「搭配拼图卡」：
// 多单品 emoji 组合 + 场合标签 + 日期，参考竞品「我的·搭配」形态
import 'package:flutter/material.dart';

import '../services/mock_data.dart';
import '../theme/app_colors.dart';

class OutfitPage extends StatelessWidget {
  const OutfitPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        // ---- 头部 ----
        Row(
          children: [
            const Text('搭配',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain)),
            const SizedBox(width: 6),
            const Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.accent),
            const Spacer(),
            const Text('历史上身 18 套',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
          ],
        ),
        const SizedBox(height: 4),
        const Text('每一套都被认真记住，穿过的不再重复推给你。',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
        const SizedBox(height: 16),

        // ---- 生成入口 ----
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('今日搭配已经在首页等你了，去穿上它。'),
                backgroundColor: AppColors.textMain,
                behavior: SnackBarBehavior.floating,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('生成今日搭配',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 16),

        // ---- 双列搭配拼图卡 ----
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: MockData.outfitCards.length,
          itemBuilder: (_, i) => _card(MockData.outfitCards[i]),
        ),
      ],
    );
  }

  Widget _card((String, String, String, List<String>) data) {
    final (occasion, date, mood, emojis) = data;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 单品拼图：2x2 emoji
          Expanded(
            child: Center(
              child: Wrap(
                spacing: 6,
                runSpacing: 2,
                alignment: WrapAlignment.center,
                children: [
                  for (final e in emojis)
                    Text(e, style: const TextStyle(fontSize: 34, height: 1.2)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 底部：场合标签 + 日期
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(occasion,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              Text(date, style: const TextStyle(fontSize: 10.5, color: AppColors.textSub)),
            ],
          ),
        ],
      ),
    );
  }
}
