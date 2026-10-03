// 试衣间「姿势」区块 —— 姿势图 + 25 种姿势库选择
//
// 为什么从 tryon_page.dart 拆出来：姿势区有 96 行、含缩略图/chip/双按钮/
// 姿势库弹层四条交互链，塞在页面里让900+ 行的文件更难改。而且这段本身
// 是完整的「一块 UI」，参数只有三样，拆出来可以独立复用与预览。
//
// 隐私设计：选中的姿势只存在调用方的内存（PosePreset 对象由本页持有），
// **不写SharedPreferences、不上传**。退出试衣间即清除。
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/pose_library.dart';
import '../theme/app_colors.dart';
import 'pose_library_sheet.dart';

class PoseSection extends StatelessWidget {
  /// 已上传的自定义姿势图字节（null = 未选）
  final Uint8List? poseBytes;

  /// 当前选中的姿势库预设（null = 未选）
  final PosePreset? preset;

  /// 换姿势图的回调（父级负责图片选择与压缩）
  final VoidCallback onPickPoseImage;

  /// 清除已选姿势（点 chip 上的 ✕）
  final VoidCallback onClearPreset;

  /// 打开姿势库弹层
  final VoidCallback onPickFromLibrary;

  /// 小按钮样式回调，交给父级保持全页视觉一致
  final Widget Function(String label, IconData icon, VoidCallback onTap) miniBtn;

  const PoseSection({
    super.key,
    required this.poseBytes,
    required this.preset,
    required this.onPickPoseImage,
    required this.onClearPreset,
    required this.onPickFromLibrary,
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
              Container(
                width: 60,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: poseBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(poseBytes!, fit: BoxFit.cover))
                    : Icon(Icons.accessibility_new_rounded,
                        color: AppColors.textHint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        poseBytes == null
                            ? '姿势图未选择（可选）'
                            : '已选姿势图（可更换）',
                        style:
                            TextStyle(fontSize: 13, color: AppColors.textSub)),
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

/// 打开姿势库弹层（25 种），点选返回；取消返回 null
Future<PosePreset?> showPoseLibrarySheet(
  BuildContext context, {
  String? currentId,
}) =>
    PoseLibrarySheet.pick(context, currentId: currentId);
