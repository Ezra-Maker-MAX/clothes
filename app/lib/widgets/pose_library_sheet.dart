// 姿势库选择弹层 —— 232 个姿势按分组 Tab + 缩略图网格展示
//
// 交互改造的原因：原来 25 个纯文字条目两列排布没问题，
// 现在 232 个（坐姿单组就121 个）纯文字列表没法用——
// 挑姿势本质上要「看着图挑」，文字描述帮不上这个忙。
// 于是改成：
//   - 顶部三个分组 Tab（坐/跪/卧），带条目数；
//   - 主体 3 列缩略图网格，图下是编码 + 中文短名；
//   - 点格子即选中并返回（保持原行为：选中就关闭弹层）；
//   - 长按/点信息图标看大图与完整说明，避免误选。
//
// 隐私说明保留在顶部：姿势图只在打开弹层时按需拉取，
// 描述只在点生成时随请求发往用户自己的模型服务。
import 'package:flutter/material.dart';

import '../services/pose_library.dart';
import '../theme/app_colors.dart';
import 'pose_thumb.dart';

class PoseLibrarySheet extends StatefulWidget {
  const PoseLibrarySheet({super.key, this.currentId});

  final String? currentId; // 当前已选（高亮 + 定位到所在分组）

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
  PoseGroup _tab = PoseGroup.sit;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentId;
    // 已选姿势所在分组默认展示，省得用户自己找
    final p = _selectedId == null ? null : PoseLibrary.byId(_selectedId!);
    if (p != null) _tab = p.group;
  }

  List<PosePreset> _listOf(PoseGroup g) => PoseLibrary.byGroup(g);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            _header(),
            const _PrivacyNote(),
            _tabs(),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                // 3 列；缩略图是竖着的全身构图，格子略高于宽才不显局促
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.78,
                ),
                itemCount: _listOf(_tab).length,
                itemBuilder: (_, i) => _card(_listOf(_tab)[i]),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选一个试衣姿势',
                    style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMain)),
                const SizedBox(height: 2),
                Text('共 ${PoseLibrary.all.length} 个 · 点图即选',
                    style:
                        TextStyle(fontSize: 11.5, color: AppColors.textHint)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          for (final g in PoseGroup.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _tabBtn(g),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabBtn(PoseGroup g) {
    final on = g == _tab;
    final n = _listOf(g).length;
    return GestureDetector(
      onTap: () => setState(() => _tab = g),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: on ? AppColors.primary : AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: on ? AppColors.primary : AppColors.divider),
        ),
        child: Column(
          children: [
            Text(PoseLibrary.groupLabels[g]!,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? Colors.white : AppColors.textMain)),
            const SizedBox(height: 1),
            Text('$n 个',
                style: TextStyle(
                    fontSize: 10,
                    color: on
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppColors.textHint)),
          ],
        ),
      ),
    );
  }

  Widget _card(PosePreset p) {
    final on = p.id == _selectedId;
    return GestureDetector(
      onTap: () => Navigator.pop(context, p),
      onLongPress: () => _showDetail(p),
      child: Container(
        decoration: BoxDecoration(
          color: on ? AppColors.primarySoft : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: on ? AppColors.primary : AppColors.divider,
              width: on ? 1.5 : 1),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PoseThumb(uri: p.imageUri),
                  // 右上角小图标：点开看大图与完整说明
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => _showDetail(p),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.info_outline_rounded,
                            size: 11, color: Colors.white),
                      ),
                    ),
                  ),
                  if (on)
                    // 不能 const：AppColors.primary 不是编译期常量
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: Icon(Icons.check_circle_rounded,
                          size: 16, color: AppColors.primary),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Flexible(
                  child: Text(p.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accent)),
                ),
              ],
            ),
            Text(p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain)),
          ],
        ),
      ),
    );
  }

  /// 详情：大图 + 说明 + 英文 prompt（方便确认要发给模型的内容）
  void _showDetail(PosePreset p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${p.code} · ${p.name}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMain)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: AppColors.textSub),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                  child: PoseThumb(
                      uri: p.imageUri, size: 220, borderRadius: 12)),
              const SizedBox(height: 12),
              Text(p.desc,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppColors.textSub)),
              const SizedBox(height: 8),
              // 分组按源站分类，名字按实际动作 —— 不一致时如实说明，
              // 否则用户会以为分类错了（47/232 条会命中，详见 pose_library.dart 文件头）
              if (p.nameLooksOffGroup) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '源站把这条归在「${PoseLibrary.groupLabels[p.group]}」，'
                    '但图中实际动作如上。分组只作浏览入口，以名称为准。',
                    style: TextStyle(fontSize: 11, height: 1.4, color: AppColors.textHint),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(p.prompt,
                    style: TextStyle(
                        fontSize: 10.5,
                        height: 1.5,
                        color: AppColors.textHint)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context, p);
                  },
                  child: const Text('选这个姿势'),
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.textHint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '参考图存在你自己的 Vercel 私密空间，只在打开姿势库时按需读取；'
              '姿势描述只在点「生成」那一刻随请求发往你自己配置的模型服务。'
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