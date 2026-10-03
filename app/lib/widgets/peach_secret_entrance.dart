// 🍑 隐蔽入口 widget —— 私密空间的唯一 UI 入口
//
// 为什么要单独成文件：这个入口是隐私设计的核心，逻辑只有十几行，
// 但**必须显眼且独立**。混在settings_page.dart 一千多行里，
// 将来做设置页改版时它极易被顺手删掉/改掉，而这种改动不会有任何编译错误、
// 也不会有任何测试失败 —— 只表现为「私密空间找不到了」。
//
// 交互设计（刻意克制，旁人看不出这是一扇门）：
//   - 嵌在页脚隐私说明文案末尾，看起来就是一枚普通表情；
//   - 需在 2 秒内连点 5 次才触发，误触无效；
//   - 触发过程中零反馈（无震动/无变色/无提示）。
//   - 已解锁 → 直接进私密空间；未解锁 → 弹密码框。
import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/private_vault_page.dart';
import '../services/private_mode_service.dart';
import '../theme/app_colors.dart';

/// 连点次数阈值（5 次）
const int kPeachTapThreshold = 5;

/// 两次点击之间的重置窗口（2 秒）
const Duration kPeachTapWindow = Duration(seconds: 2);

/// 🍑 隐蔽入口。放进页脚文案末尾即可。[onUnlocked] 用于已解锁时的自定义跳转，
/// 留空则默认 push 私密空间页。
class PeachSecretEntrance extends StatefulWidget {
  final VoidCallback? onUnlocked;

  const PeachSecretEntrance({super.key, this.onUnlocked});

  @override
  State<PeachSecretEntrance> createState() => _PeachSecretEntranceState();
}

class _PeachSecretEntranceState extends State<PeachSecretEntrance> {
  int _taps = 0;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _onTap() {
    // 每次点击都重置倒计时：要求是「连续 5 次」，中间停顿超过 2 秒就重新算
    _reset?.cancel();
    _reset = Timer(kPeachTapWindow, () {
      if (mounted) setState(() => _taps = 0);
    });
    _taps++;
    if (_taps < kPeachTapThreshold) return; // 未达阈值：零反馈，这是刻意设计

    _taps = 0;
    _reset?.cancel();

    if (PrivateModeService.unlocked.value) {
      final cb = widget.onUnlocked;
      if (cb != null) {
        cb();
        return;
      }
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const PrivateVaultPage()));
    } else {
      // 未解锁：交给外部的密码流程（密码校验+ 令牌颁发在 service 层）
      _askPassword(context);
    }
  }

  /// 未解锁时的密码输入。做成对话框而非塞回 settings_page：
  /// 这样本文件只依赖 service，不依赖任何页面，测试与复用都干净。
  Future<void> _askPassword(BuildContext context) async {
    final ctrl = TextEditingController();
    bool verifying = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState2) => AlertDialog(
          backgroundColor: AppColors.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('私密空间',
              style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMain)),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '请输入私密模式密码',
              hintStyle:
                  TextStyle(fontSize: 13, color: AppColors.textHint),
            ),
            onSubmitted: (_) => Navigator.pop(ctx2, true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2, false),
              child: Text('取消', style: TextStyle(color: AppColors.textSub)),
            ),
            TextButton(
              onPressed: verifying
                  ? null
                  : () async {
                      if (verifying) return;
                      setState2(() => verifying = true);
                      final r = await PrivateModeService.verify(ctrl.text);
                      if (!ctx2.mounted) return;
                      if (r.$1) {
                        await PrivateModeService.unlockAndRemember(r.$3);
                        if (!ctx2.mounted) return;
                        Navigator.pop(ctx2, true);
                      } else {
                        setState2(() => verifying = false);
                        ScaffoldMessenger.of(ctx2).showSnackBar(SnackBar(
                          content: Text(r.$2.isEmpty ? '验证失败' : r.$2),
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    },
              child: Text(verifying ? '验证中…' : '解锁',
                  style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (ok == true && mounted) {
      // 验证通过：直接进入私密空间。await 之后重新检查 mounted，
      // 不拿可能已失效的 BuildContext 去导航。
      await Navigator.of(this.context).push(
          MaterialPageRoute(builder: (_) => const PrivateVaultPage()));
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      // 透明手势容差：小 emoji 的可点区域偏小，容易被判定为误触而不响应
      behavior: HitTestBehavior.opaque,
      child: const Text(' 🍑', style: TextStyle(fontSize: 11.5)),
    );
  }
}
