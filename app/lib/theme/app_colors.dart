// 「搭配测试」色彩规范 —— 严格对齐 UI/UX 视觉规范
//
// 设计基调：暖调米白底 + 纯白大圆角卡片 + 莫兰迪紫主色 + 蜜桃橙强调
// 原则：克制、呼吸感、莫兰迪低饱和
import 'package:flutter/material.dart';

abstract final class AppColors {
  // ---- 基底 ----
  /// 页面背景：暖调米白/奶油色
  static const Color bg = Color(0xFFF8F9FA);

  /// 卡片：纯白
  static const Color card = Colors.white;

  /// 分割线/浅灰
  static const Color divider = Color(0xFFEDEBF2);

  // ---- 主色调：莫兰迪紫 ----
  /// 主按钮「就穿这套」、底部导航选中态、标题重点
  static const Color primary = Color(0xFF715F9B);
  static const Color primarySoft = Color(0xFFEFEAF6); // 紫的 5% 底，用于 chip/标签底色

  // ---- 强调色：柔和橙/蜜桃色 ----
  /// 统计数字、「舒适温度」标签
  static const Color accent = Color(0xFFE8835C);
  static const Color accentSoft = Color(0xFFFDEEE6); // 蜜桃浅底

  // ---- 文字 ----
  static const Color textMain = Color(0xFF332F40);   // 近黑带紫调
  static const Color textSub = Color(0xFF8D89A0);    // 次级灰紫
  static const Color textHint = Color(0xFFB6B2C7);   // 弱提示

  // ---- 单品图卡底色（莫兰迪渐变素材色）----
  static const Color itemTop = Color(0xFFEFE7DC);    // 燕麦米
  static const Color itemBottom = Color(0xFFDCE6EF); // 雾蓝
  static const Color itemShoe = Color(0xFFF3E3E0);   // 裸粉

  /// 卡片圆角 16px（视觉规范）
  static const double radius = 16;

  /// 极轻微呼吸感阴影
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF715F9B).withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
}
