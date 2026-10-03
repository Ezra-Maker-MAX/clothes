// 姿势库选择弹层 —— 25 种姿势按 K/S/L 三组折叠展示，点选即回传
//
// 交互：默认全部折叠（25 个一次铺开会眼花），点组名展开；
// 已选中的姿势高亮 + 显示编码；顶部给一句隐私说明（纯文本描述，不留痕）。
import 'package:flutter/material.dart';

import '../services/pose_library.dart';
import '../theme/app_colors.dart';

class PoseLibrarySheet extends StatefulWidget {
  const PoseLibrarySheet({super.key, this.currentId});

  final String? currentId; // 当前已选（高亮 + 滚动定位）

  @override
  State<PoseLibrarySheet> createState() => _PoseLibrarySheetState();

  /// 便捷入口：弹出姿势库弹层，返回点选的姿势（直接关闭/未选返回 null）
  static Future<PosePreset?> pick(BuildContext context, {String? currentId}) {
    return showModalBottomSheet<PosePreset>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PoseLibrarySheet(currentId: currentId),
    );
  }
}

class _PoseLibrarySheetState extends State<PoseLibrarySheet> {
  final _expanded = <PoseGroup, bool>{};
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentId;
    // 已选姿势所在组默认展开，别的组收着
    if (_selectedId != null) {
      final p = PoseLibrary.byId(_selectedId!);
      if (p != null) _expanded[p.group] = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.74,
        child: Column(
          children: [
            _header(),
            const _PrivacyNote(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  for (final g in PoseGroup.values) _groupSection(g),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text('选一个试衣姿势',
                style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMain)),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }

  Widget _groupSection(PoseGroup g) {
    final list = PoseLibrary.byGroup(g);
    final open = _expanded[g] ?? false;
    final groupSelected =
        list.any((p) => p.id == _selectedId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: groupSelected
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.divider),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded[g] = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Text(PoseLibrary.groupLabels[g]!,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: groupSelected
                              ? AppColors.primary
                              : AppColors.textMain)),
                  const SizedBox(width: 8),
                  Text('${list.length} 个',
                      style:
                          TextStyle(fontSize: 11.5, color: AppColors.textHint)),
                  const Spacer(),
                  if (groupSelected) ...[
                    Icon(Icons.check_circle_rounded,
                        size: 15, color: AppColors.primary),
                    const SizedBox(width: 5),
                  ],
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 19, color: AppColors.textSub),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(PoseLibrary.groupHints[g]!,
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textHint)),
                  const SizedBox(height: 8),
                  // 网格：一行两个，姿势名 + 编码，好扫视
                  ...List.generate((list.length + 1) ~/ 2, (row) {
                    return Row(
                      children: [
                        for (var col = 0; col < 2; col++) ...[
                          if (row * 2 + col < list.length)
                            Expanded(child: _tile(list[row * 2 + col]))
                          else
                            const Spacer(),
                          if (col == 0) const SizedBox(width: 8),
                        ],
                      ],
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(PosePreset p) {
    final on = p.id == _selectedId;
    return GestureDetector(
      onTap: () => Navigator.pop(context, p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: on ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: on ? AppColors.primary : AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: on ? Colors.white.withValues(alpha: 0.22) : AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(p.code,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: on ? Colors.white : AppColors.accent)),
                ),
                const Spacer(),
                if (on)
                  const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white),
              ],
            ),
            const SizedBox(height: 6),
            Text(p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: on ? Colors.white : AppColors.textMain)),
            const SizedBox(height: 2),
            Text(p.desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: on ? Colors.white.withValues(alpha: 0.85) : AppColors.textHint)),
          ],
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.textHint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '姿势只以文字描述随请求发往你自己配置的模型服务；'
              '你的选择只留在本页内存里，退出即清除，不留记录。',
              style: TextStyle(
                  fontSize: 10.5,
                  height: 1.5,
                  color: AppColors.textHint.withValues(alpha: 0.95)),
            ),
          ),
        ],
      ),
    );
  }
}
