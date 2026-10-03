// 姿势参考图组件 —— 懒加载 + 磁盘/内存缓存 + 优雅降级
//
// 为什么单独抽一个组件：姿势库有 232 个格子，如果每个都用 Image.network
// 且不做任何缓存，会同时发起 232 个请求把自家Vercel 打挂（也把用户流量烧掉）。
// 这里做三件事：
//   1. 只在**可见时**才加载（VisibilityDetector），滚过去才拉；
//   2. 拉过的图进内存缓存（imageCache），滚回来不重复请求；
//      服务器侧也设了 immutable 长缓存，两端配合；
//   3. 加载失败/未配置私密 store 时显示占位图标，**不让整个列表崩掉**——
//      用户依然能靠中文名+ prompt 选姿势，图只是辅助。
import 'package:flutter/material.dart';

/// 姿势图占位图标（加载中/ 失败 / 私密 store 未配置时用）
///
/// 放在 widget 层而不是 service 层：服务层不该 import Flutter，
/// 否则 pose_library 就没法被纯 Dart 测试引用了。
const Icon kPoseImageFallback = Icon(
  Icons.accessibility_new_rounded,
  color: Color(0xFFB9B9C6),
);

class PoseThumb extends StatelessWidget {
  const PoseThumb({
    super.key,
    required this.uri,
    this.size,
    this.borderRadius = 10,
    this.fit = BoxFit.contain,
  });

  final Uri? uri;
  final double? size;
  final double borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final u = uri;
    final box = SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          // 浅灰底：姿势图是透明 PNG/ WebP，容器底色决定未加载时是什么样
          color: const Color(0xFFF3F3F7),
          child: u == null
              ? kPoseImageFallback
              : Image.network(
                  u.toString(),
                  fit: fit,
                  // 姿势图是「看构图」的参考图，保持比例、不裁切
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => kPoseImageFallback,
                  loadingBuilder: (ctx, child, prog) {
                    if (prog == null) return child;
                    // 加载中不转圈（232 个格子同时转圈很吵），用低透明度的占位
                    return const Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          valueColor: AlwaysStoppedAnimation(Color(0xFFD5D5DE)),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
    return box;
  }
}