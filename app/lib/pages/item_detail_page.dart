// 单品详情页 —— 参考竞品「单品详情」形态：
// 顶部大图卡 + 详情字段行（可编辑项点击修改）+ 搭配记录 + 底部 编辑/删除
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/item_form_sheet.dart';

class ItemDetailPage extends StatefulWidget {
  const ItemDetailPage({super.key, required this.item});

  final ItemInfo item;

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  late ItemInfo _item;
  List<HistoryEntry> _wornWith = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _loadHistory();
  }

  /// 这件单品参与过的搭配记录（最多展示 5 条）
  Future<void> _loadHistory() async {
    if (ApiClient.useMock) {
      setState(() => _loadingHistory = false);
      return;
    }
    try {
      final all = await ApiClient.getHistory();
      if (!mounted) return;
      setState(() {
        _wornWith = all.where((e) => e.itemIds.contains(_item.id)).take(5).toList();
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ItemFormSheet(item: _item),
    );
    if (saved == true && mounted) {
      // 编辑成功：从衣橱最新数据里找这件（表单保存后由衣橱页刷新，这里本地同步字段）
      _snack('已更新，衣橱列表同步刷新');
      Navigator.pop(context, true);
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('删掉这件？',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        content: Text('「${_item.name}」会从衣橱收走，穿过的历史记录不受影响。',
            style: const TextStyle(fontSize: 13.5, color: AppColors.textSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再想想', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删掉', style: TextStyle(color: Color(0xFFB4654A), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await ApiClient.deleteWardrobeItem(_item.id);
      if (mounted) {
        _snack('已收进箱底，衣橱少一件');
        Navigator.pop(context, true);
      }
    } catch (e) {
      _snack('没删掉：${e.toString().substring(0, e.toString().length.clamp(0, 80))}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textMain),
        ),
        title: const Text('单品详情',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          // ---- 大图卡（有图显示图，无图显示分类 emoji 色块） ----
          Stack(
            children: [
              Container(
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppColors.radius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _item.gradient,
                  ),
                ),
                child: Center(
                  child: _item.imageUrl != null && _item.imageUrl!.startsWith('http')
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(AppColors.radius),
                          child: Image.network(
                            _item.imageUrl!,
                            width: double.infinity,
                            height: 260,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Text(_item.emoji, style: const TextStyle(fontSize: 110, height: 1.1)),
                          ),
                        )
                      : Text(_item.emoji, style: const TextStyle(fontSize: 110, height: 1.1)),
                ),
              ),
              // 右下角「换图」快捷钮（打开编辑表单，图片区在顶部）
              Positioned(
                right: 10,
                bottom: 10,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _edit,
                    child: const Padding(
                      padding: EdgeInsets.all(9),
                      child: Icon(Icons.image_rounded, size: 20, color: AppColors.textSub),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(_item.name,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textMain)),
          ),
          const SizedBox(height: 18),

          // ---- 详情字段行 ----
          _field('状态', '在穿'),
          _field('分类', _item.categoryLabel),
          _field('颜色', _item.colorName ?? '未记录'),
          _field('品牌', _item.brand ?? '未记录'),
          _field('价格', _item.price == null ? '未记录' : '¥${_priceText(_item.price!)}'),
          _field('单次穿着成本', _item.costPerWear),
          _field('穿着次数', '${_item.wearCount} 次'),
          _field('最近穿着', _item.lastWornAt == null ? '还没上过身' : _shortDate(_item.lastWornAt!)),
          const SizedBox(height: 18),

          // ---- 搭配记录 ----
          Row(
            children: [
              const Text('穿过它的时候',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textMain)),
              const Spacer(),
              Text('${_item.wearCount} 次上身',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSub)),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingHistory)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
            )
          else if (_wornWith.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppColors.radius),
                boxShadow: AppColors.softShadow,
              ),
              child: const Center(
                child: Text('还没有记录。回首页「换一套」，让它出场。',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
              ),
            )
          else
            ..._wornWith.map(_historyRow),

          const SizedBox(height: 24),

          // ---- 底部操作：编辑 / 删除 ----
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _edit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMain,
                    side: const BorderSide(color: AppColors.divider),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('编辑', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB4654A),
                    side: const BorderSide(color: Color(0xFFD8B7A9)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('删除', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 字段行：左标签 + 右值（参考竞品详情行样式） ----
  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppColors.softShadow,
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.textSub)),
            const Spacer(),
            Text(value,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textMain)),
          ],
        ),
      ),
    );
  }

  Widget _historyRow(HistoryEntry e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          Text(e.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(e.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSub)),
          ),
          const SizedBox(width: 8),
          Text(e.date, style: const TextStyle(fontSize: 11.5, color: AppColors.textHint)),
        ],
      ),
    );
  }

  String _shortDate(String iso) {
    final parts = iso.split(RegExp(r'[T ]')).first.split('-');
    if (parts.length != 3) return iso;
    return '${int.tryParse(parts[1]) ?? ''}月${int.tryParse(parts[2]) ?? ''}日';
  }

  String _priceText(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        backgroundColor: AppColors.textMain,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }
}
