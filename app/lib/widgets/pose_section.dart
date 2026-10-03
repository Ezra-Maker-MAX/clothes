// 试衣间「姿势」区块 —— 姿势图 + 姿势库选择
//
// 为什么从 tryon_page.dart 拆出来：姿势区有缩略图/chip/双按钮/
// 姿势库弹层/参考图开关五条交互链，塞在页面里让 900+ 行的文件更难改。
// 而且这段本身是完整的「一块 UI」，参数只有几样，拆出来可以独立复用与预览。
//
// 隐私设计：选中的姿势只存在调用方的内存（PosePreset 对象由本页持有），
// **不写 SharedPreferences、不上传**。退出试衣间即清除。
// 参考图是否随生成请求发给模型由用户当次勾选（sendRefImage），默认关闭。
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/pose_library.dart';
import '../theme/app_colors.dart';
import 'pose_library_sheet.dart';
import 'pose_thumb.dart';

class PoseSection extends StatelessWidget {
  /// 已上传的自定义姿势图字节（null = 未选）
  final Uint8List? poseBytes;

  /// 当前选中的姿势库预设（null = 未选）
  final PosePreset? preset;

  /// 是否把姿势库的参考图也发给模型（默认 false）
  final bool sendRefImage;

  /// 换姿势图的回调（父级负责图片选择与压缩）
  final VoidCallback onPickPoseImage;

  /// 清除已选姿势（点 chip 上的 ✕）
  final VoidCallback onClearPreset;

  /// 打开姿势库弹层
  final VoidCallback onPickFromLibrary;

  /// 切换「把参考图发给模型」
  final VoidCallback onToggleSendRefImage;

  /// 小按钮样式回调，交给父级保持全页视觉一致
  final Widget Function(String label, IconData icon, VoidCallback onTap) miniBtn;

  const PoseSection({
    super.key,
    required this.poseBytes,
    required this.preset,
    required this.sendRefImage,
    required this.onPickPoseImage,
    required this.onClearPreset,
    required this.onPickFromLibrary,
    required this.onToggleSendRefImage,
    required this.miniBtn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 缩略图：优先显示用户自己传的姿势图；否则显示姿势库选中的参考图
              Container(
                width: 60,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: poseBytes != null
                    ? Image.memory(poseBytes!, fit: BoxFit.cover)
                    : preset != null
                        ? PoseThumb(uri: preset!.imageUri,
                            size: 80, borderRadius: 0)
                        : Icon(Icons.accessibility_new_rounded,
                            color: AppColors.textHint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        poseBytes == null && preset == null
                            ? '姿势未选择（可选）'
                            : poseBytes != null
                                ? '已传自定义姿势图'
                                : '已选姿势库姿势',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSub)),
                    const SizedBox(height: 6),
                    Text(
                        preset == null
                            ? '从姿势库挑一个，或自己传图'
                            : preset!.desc,
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: AppColors.textHint)),
                    if (preset != null) ...[
                      const SizedBox(height: 8),
                      // 已选姿势 chip：点一下即取消；只存内存，退出试衣间即清除
                      GestureDetector(
                        onTap: onClearPreset,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${preset!.code} · ${preset!.name}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary)),
                              const SizedBox(width: 5),
                              Icon(Icons.close_rounded,
                                  size: 14, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // 参考图开关：只有选了姿势库姿势才有意义
          if (preset != null) ...[
            const SizedBox(height: 10),
            _SendRefToggle(
              enabled: sendRefImage,
              onChanged: onToggleSendRefImage,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Center(
                  child: miniBtn('传姿势图', Icons.add_photo_alternate_rounded,
                      onPickPoseImage),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Center(
                  child: miniBtn(preset == null ? '从姿势库选' : '换个姿势',
                      Icons.accessibility_new_rounded, onPickFromLibrary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 「把这张参考图也发给模型」开关
///
/// 为什么默认关闭：姿势库的参考图存在自家 Vercel 私密空间，
/// 原来的隐私承诺是「姿势只以文字描述发给模型」。打开这个开关意味着
/// 图片本身也会经手机发给你的模型服务——这通常能让姿势还原更准，
/// 但确实改变了数据流向，所以交由用户当次显式选择，不做默认。
class _SendRefToggle extends StatelessWidget {
  const _SendRefToggle({required this.enabled, required this.onChanged});

  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: enabled ? AppColors.primarySoft : AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: enabled ? AppColors.primary : AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(
              enabled
                  ? Icons.image_outlined
                  : Icons.image_not_supported_outlined,
              size: 15,
              color: enabled ? AppColors.primary : AppColors.textHint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                enabled
                    ? '参考图会发给模型（姿势还原更准）'
                    : '只用文字描述，不发送参考图',
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color:
                        enabled ? AppColors.primary : AppColors.textHint),
              ),
            ),
            Switch(
              value: enabled,
              onChanged: (_) => onChanged(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

/// 打开姿势库弹层（232 个），点选返回；取消返回 null
Future<PosePreset?> showPoseLibrarySheet(
  BuildContext context, {
  String? currentId,
}) =>
    PoseLibrarySheet.pick(context, currentId: currentId);