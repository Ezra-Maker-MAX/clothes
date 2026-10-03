// 「搭配测试」色彩规范 —— 双主题：日常莫兰迪 / 私密暗夜酒红
//
// 日常基调：暖调米白底 + 纯白大圆角卡片 + 莫兰迪紫主色 + 蜜桃橙强调
// 私密基调（内衣模式）：暗夜酒红丝绒底 + 玫瑰红主色 + 裸粉金强调，
//   专为私密空间设计——暧昧、低照度、只属于主人自己。
//
// 切换机制：privateMode 开关一翻，根节点 ValueListenableBuilder 重建整树，
// 所有字段都是 getter，重建后全 App 换色（const 上下文已全部解除）。
import 'package:flutter/material.dart';

abstract final class AppColors {
  /// 私密模式开关（true = 暗夜酒红主题）。只由 PrivateModeService 修改。
  static bool privateMode = false;

  // ════ 日常色板（莫兰迪 · 米白底） ════
  static const Color _bg = Color(0xFFF8F9FA);         // 页面背景：暖调米白
  static const Color _card = Colors.white;            // 卡片：纯白
  static const Color _divider = Color(0xFFEDEBF2);    // 分割线
  static const Color _primary = Color(0xFF715F9B);    // 主色：莫兰迪紫
  static const Color _primarySoft = Color(0xFFEFEAF6);// 紫的 5% 底
  static const Color _accent = Color(0xFFE8835C);     // 强调：蜜桃橙
  static const Color _accentSoft = Color(0xFFFDEEE6); // 蜜桃浅底
  static const Color _textMain = Color(0xFF332F40);   // 近黑带紫调
  static const Color _textSub = Color(0xFF8D89A0);    // 次级灰紫
  static const Color _textHint = Color(0xFFB6B2C7);   // 弱提示
  static const Color _itemTop = Color(0xFFEFE7DC);    // 单品图卡底：燕麦米
  static const Color _itemBottom = Color(0xFFDCE6EF); // 雾蓝
  static const Color _itemShoe = Color(0xFFF3E3E0);   // 裸粉

  // ════ 私密色板（暗夜酒红 · 暧昧诱惑） ════
  static const Color _pBg = Color(0xFF160F13);          // 暗夜底：近黑透酒红
  static const Color _pCard = Color(0xFF251822);        // 深酒绒卡片
  static const Color _pDivider = Color(0xFF3B2833);     // 暗玫瑰分割线
  static const Color _pPrimary = Color(0xFFE0506E);     // 主色：玫瑰红（暧昧主调）
  static const Color _pPrimarySoft = Color(0xFF3A222C); // 玫瑰暗底
  static const Color _pAccent = Color(0xFFE8A98F);      // 强调：裸粉金
  static const Color _pAccentSoft = Color(0xFF3C2B28);  // 裸粉暗底
  static const Color _pTextMain = Color(0xFFF5E9ED);    // 粉白主文字
  static const Color _pTextSub = Color(0xFFB89AA6);     // 次级干玫瑰
  static const Color _pTextHint = Color(0xFF7F6673);    // 弱提示
  static const Color _pItemTop = Color(0xFF3C2433);     // 单品图卡底：酒红调
  static const Color _pItemBottom = Color(0xFF2D1D2C);  // 暗紫调
  static const Color _pItemShoe = Color(0xFF452634);    // 深玫瑰调

  // ---- 对外 getter（日常 ⇄ 私密一键切换） ----

  /// 页面背景
  static Color get bg => privateMode ? _pBg : _bg;

  /// 卡片
  static Color get card => privateMode ? _pCard : _card;

  /// 分割线/浅灰
  static Color get divider => privateMode ? _pDivider : _divider;

  /// 主色：主按钮「就穿这套」、底部导航选中态、标题重点
  /// （日常=莫兰迪紫 / 私密=玫瑰红）
  static Color get primary => privateMode ? _pPrimary : _primary;

  /// 主色浅底，用于 chip/标签底色
  static Color get primarySoft => privateMode ? _pPrimarySoft : _primarySoft;

  /// 强调色：统计数字、「舒适温度」标签（日常=蜜桃橙 / 私密=裸粉金）
  static Color get accent => privateMode ? _pAccent : _accent;

  /// 强调色浅底
  static Color get accentSoft => privateMode ? _pAccentSoft : _accentSoft;

  /// 主文字
  static Color get textMain => privateMode ? _pTextMain : _textMain;

  /// 次级文字
  static Color get textSub => privateMode ? _pTextSub : _textSub;

  /// 弱提示文字
  static Color get textHint => privateMode ? _pTextHint : _textHint;

  /// 单品图卡底色（莫兰迪渐变素材色 / 私密暗调渐变）
  static Color get itemTop => privateMode ? _pItemTop : _itemTop;
  static Color get itemBottom => privateMode ? _pItemBottom : _itemBottom;
  static Color get itemShoe => privateMode ? _pItemShoe : _itemShoe;

  /// 卡片圆角 16px（视觉规范，两主题共用）
  static const double radius = 16;

  /// 卡片阴影：日常极轻紫晕 / 私密深酒红光晕（低照度氛围感）
  static List<BoxShadow> get softShadow => privateMode
      ? [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFFE0506E).withValues(alpha: 0.10),
            blurRadius: 34,
            offset: const Offset(0, 2),
          ),
        ]
      : [
          BoxShadow(
            color: const Color(0xFF715F9B).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ];
}
