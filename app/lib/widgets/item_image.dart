// 单品图卡：三张圆角图之一
//
// 第二阶段：emoji + 莫兰迪渐变底（离线稳定，观感统一）
// 第三阶段：imageUrl 非空时走 Image.network（Vercel Blob 真图），
//           加载失败自动降级回本卡片，永不白块。
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';

class ItemImage extends StatelessWidget {
  const ItemImage({super.key, required this.item, this.height = 150});

  final ItemInfo item;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: item.imageUrl != null
            ? Image.network(
                item.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  /// 本地渲染占位：莫兰迪渐变 + 大号单品 emoji + 底部名称
  Widget _placeholder() {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: item.gradient,
      )),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(item.emoji, style: const TextStyle(fontSize: 52, height: 1.1)),
          const SizedBox(height: 8),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain,
            ),
          ),
          if (item.colorName != null)
            Text(item.colorName!,
                style: const TextStyle(fontSize: 10.5, color: AppColors.textSub)),
        ],
      ),
    );
  }
}
