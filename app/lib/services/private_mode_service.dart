// 私密模式（内衣模式）门禁服务
//
// ── 密码安全 ──
// 密码只存在 Vercel 环境变量 PRIVATE_MODE_PASSWORD 里，走 /api/private-verify
// 服务端比对；本地存储与安装包里没有密码明文。
//
// ── 解锁状态 ──
// 验证通过后本地只记「解锁时间戳」（不是密码），24 小时内重启 App 免重复输入；
// 「退出私密模式」立即清掉时间戳并切回日常主题。
//
// ── 主题联动 ──
// unlocked 是全局 ValueNotifier：main.dart 监听它重建整树，
// AppColors.privateMode 随之切换，全 App 从莫兰迪米白 → 暗夜酒红。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import 'api_client.dart';

class PrivateModeService {
  PrivateModeService._();

  /// 全局解锁状态：main.dart 监听它做整树重建换肤
  static final ValueNotifier<bool> unlocked = ValueNotifier(false);

  static const String _tsKey = 'private_unlock_ts';
  static const String _tokenKey = 'private_token';

  /// 解锁有效期：24 小时内免重复输入密码
  static const Duration _validFor = Duration(hours: 24);

  /// 数据接口令牌（服务端 HMAC 签发，private-profile 读写用）；未解锁为 null
  static String? _token;

  /// App 启动时调用：24 小时内解锁过就直接恢复私密主题
  static Future<void> init() async {
    bool on = false;
    try {
      final sp = await SharedPreferences.getInstance();
      final ts = sp.getInt(_tsKey) ?? 0;
      on = ts > 0 &&
          DateTime.now().millisecondsSinceEpoch - ts < _validFor.inMilliseconds;
      _token = sp.getString(_tokenKey);
    } catch (_) {
      on = false;
    }
    _apply(on);
  }

  /// 向服务端验证密码（密码本身不落任何本地存储）
  /// 返回 (是否通过, 失败提示)；通过时第三位为数据接口令牌
  static Future<(bool, String, String?)> verify(String password) =>
      ApiClient.verifyPrivatePassword(password);

  /// 验证通过后调用：切主题 + 记住 24 小时 + 存数据接口令牌
  static Future<void> unlockAndRemember(String? token) async {
    _apply(true);
    _token = token;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_tsKey, DateTime.now().millisecondsSinceEpoch);
      if (token != null && token.isNotEmpty) {
        await sp.setString(_tokenKey, token);
      }
    } catch (_) {}
  }

  /// 当前数据接口令牌（私密空间云端读写用）
  static String? get token => _token;

  /// 退出私密模式：立即切回日常主题并清除解锁记录与令牌
  static Future<void> lock() async {
    _apply(false);
    _token = null;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_tsKey);
      await sp.remove(_tokenKey);
    } catch (_) {}
  }

  static void _apply(bool on) {
    AppColors.privateMode = on;
    unlocked.value = on;
    // 状态栏图标亮度跟主题走：暗底用亮图标，亮底用暗图标
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: on ? Brightness.light : Brightness.dark,
      statusBarBrightness: on ? Brightness.dark : Brightness.light,
    ));
  }
}
