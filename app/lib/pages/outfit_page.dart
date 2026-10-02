// 搭配页 —— 参考竞品「搭配」形态：
// 双列搭配拼图卡（真实历史组合渲染，DIY 有角标）+ 右下悬浮「+」DIY 搭配
// P0：拼图卡背景色可换（对齐 lookie「DIY 搭配背景编辑」；本地偏好，不落库）
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/mock_data.dart';
import '../theme/app_colors.dart';

/// 可选卡底色（浅色系保证文字可读）：白 / 米杏 / 雾蓝 / 裸粉 / 淡紫 / 薄荷
const List<Color> _kBgChoices = [
  Color(0xFFFFFFFF),
  Color(0xFFFDF6EC),
  Color(0xFFEAF1F8),
  Color(0xFFF7E9E6),
  Color(0xFFEFEAF6),
  Color(0xFFE6F2EC),
];

class OutfitPage extends StatefulWidget {
  const OutfitPage({super.key});

  @override
  State<OutfitPage> createState() => _OutfitPageState();
}

class _OutfitPageState extends State<OutfitPage> {
  bool _loading = false;
  String? _errorDetail;
  List<HistoryEntry> _history = [];
  List<ItemInfo> _wardrobe = [];
  Color _bgColor = _kBgChoices.first; // 拼图卡底色（本地偏好持久化）

  bool get _real => !ApiClient.useMock;

  @override
  void initState() {
    super.initState();
    _loadBgPref();
    if (_real) _load();
  }

  Future<void> _loadBgPref() async {
    final sp = await SharedPreferences.getInstance();
    final idx = sp.getInt('diy_bg_color') ?? 0;
    if (mounted && idx >= 0 && idx < _kBgChoices.length) {
      setState(() => _bgColor = _kBgChoices[idx]);
    }
  }

  Future<void> _pickBg(Color c) async {
    setState(() => _bgColor = c);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('diy_bg_color', _kBgChoices.indexOf(c));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.getHistory(),
        ApiClient.getWardrobe(),
      ]);
      if (mounted) {
        setState(() {
          _history = results[0] as List<HistoryEntry>;
          _wardrobe = results[1] as List<ItemInfo>;
          _errorDetail = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorDetail = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ItemInfo? _byId(String id) {
    for (final i in _wardrobe) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// 一套的 emoji 列表：按 itemIds 映射衣橱单品；映射不到用场合 emoji 兜底
  List<String> _emojisOf(HistoryEntry e) {
    if (e.itemIds.isEmpty) return [e.emoji];
    final emojis = e.itemIds.map((id) => _byId(id)?.emoji).whereType<String>().toList();
    return emojis.isEmpty ? [e.emoji] : emojis;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 96),
          children: [
            _header(),
            const SizedBox(height: 10),
            _bgPalette(),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (!_real)
              _mockCards()
            else if (_history.isEmpty)
              _emptyView()
            else
              _realCards(),
          ],
        ),
        // ---- 右下悬浮「+」：DIY 搭配（参考竞品搭配页悬浮钮） ----
        if (!_loading)
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton(
              heroTag: 'diy_outfit',
              onPressed: _openDiySheet,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _header() {
    final countText = _real ? '已上身 ${_history.length} 套' : '历史上身 18 套';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('搭配',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain)),
            const SizedBox(width: 6),
            const Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.accent),
            const Spacer(),
            Text(countText, style: const TextStyle(fontSize: 12.5, color: AppColors.textSub)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _real ? '穿过的每一套都记着，右下角 + 自己动手配一套。' : '每一套都被认真记住，穿过的不再重复推给你。',
          style: const TextStyle(fontSize: 12.5, color: AppColors.textSub),
        ),
        if (_errorDetail != null) ...[
          const SizedBox(height: 2),
          Text('数据加载失败：$_errorDetail',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: AppColors.textHint)),
        ],
      ],
    );
  }

  /// 背景色板：小圆点一排，当前色描边选中（对齐 lookie 的 DIY 背景编辑）
  Widget _bgPalette() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Text('卡底色',
              style: TextStyle(fontSize: 11.5, color: AppColors.textHint)),
          const SizedBox(width: 10),
          for (final c in _kBgChoices) ...[
            GestureDetector(
              onTap: () => _pickBg(c),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    width: _bgColor == c ? 2 : 1,
                    color: _bgColor == c ? AppColors.primary : AppColors.divider,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          const Text('点一下换背景',
              style: TextStyle(fontSize: 10.5, color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _emptyView() {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          const Text('🪞', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 10),
          const Text('还没有搭配记录',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textMain)),
          const SizedBox(height: 6),
          const Text('去首页「就穿这套」，或点右下角 + 自己配一套',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
        ],
      ),
    );
  }

  // ---- 真实数据：双列拼图卡 ----
  Widget _realCards() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: _history.length,
      itemBuilder: (_, i) {
        final e = _history[i];
        final emojis = _emojisOf(e);
        return _card(
          emojis: emojis,
          occasion: e.occasionLabel,
          date: e.date,
          isDiy: e.source == 'manual',
          bgColor: _bgColor,
        );
      },
    );
  }

  // ---- mock 兜底 ----
  Widget _mockCards() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: MockData.outfitCards.length,
      itemBuilder: (_, i) {
        final (occasion, date, _, emojis) = MockData.outfitCards[i];
        return _card(emojis: emojis, occasion: occasion, date: date, isDiy: false, bgColor: _bgColor);
      },
    );
  }

  // ---- 拼图卡：多单品 emoji 组合 + 场合标签 + 日期（+ DIY 角标；底色可选） ----
  Widget _card({
    required List<String> emojis,
    required String occasion,
    required String date,
    required bool isDiy,
    Color bgColor = AppColors.card,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final e in emojis)
                        Text(e, style: const TextStyle(fontSize: 34, height: 1.2)),
                    ],
                  ),
                ),
                if (isDiy)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('DIY',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(occasion,
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              Text(date, style: const TextStyle(fontSize: 10.5, color: AppColors.textSub)),
            ],
          ),
        ],
      ),
    );
  }

  /// DIY 搭配：分类三选一 → 存为一套
  Future<void> _openDiySheet() async {
    if (!_real) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('今日搭配已经在首页等你了，去穿上它。'),
          backgroundColor: AppColors.textMain,
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DiyOutfitSheet(wardrobe: _wardrobe),
    );
    if (saved == true) {
      _toast('配好了，这套已经记进搭配');
      _load();
    }
  }

  void _toast(String msg) {
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

/// DIY 选品器：上衣 / 下装（裤装+裙装）/ 鞋子 各选一件 → 存为一套
class DiyOutfitSheet extends StatefulWidget {
  const DiyOutfitSheet({super.key, required this.wardrobe});

  final List<ItemInfo> wardrobe;

  @override
  State<DiyOutfitSheet> createState() => _DiyOutfitSheetState();
}

class _DiyOutfitSheetState extends State<DiyOutfitSheet> {
  String? _top;
  String? _bottom;
  String? _shoe;
  bool _saving = false;

  List<ItemInfo> _of(List<String> cats) =>
      widget.wardrobe.where((i) => cats.contains(i.categoryLabel)).toList();

  ItemInfo? _byId(String? id) {
    if (id == null) return null;
    for (final i in widget.wardrobe) {
      if (i.id == id) return i;
    }
    return null;
  }

  Future<void> _save() async {
    final top = _byId(_top);
    final bottom = _byId(_bottom);
    final shoe = _byId(_shoe);
    if (top == null || bottom == null || shoe == null) {
      _snack('上衣、下装、鞋子各选一件才能成套');
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.saveManualOutfit([top, bottom, shoe]);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        var msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        if (msg.length > 80) msg = '${msg.substring(0, 80)}…';
        _snack('没配上：$msg');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('DIY 搭配',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSub),
                ),
              ],
            ),
            const Text('从你的衣橱里挑三件，配一套今天想穿的。',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSub)),
            const SizedBox(height: 14),
            _section('上衣', _of(['上衣']), _top, (id) => setState(() => _top = id)),
            _section('下装', _of(['裤装', '裙装']), _bottom, (id) => setState(() => _bottom = id)),
            _section('鞋子', _of(['鞋子']), _shoe, (id) => setState(() => _shoe = id)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('存为我的搭配',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<ItemInfo> items, String? selectedId, ValueChanged<String> onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$title · ${items.length}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSub)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Text('衣橱里还没有这一类，先去「衣橱」添加',
                style: TextStyle(fontSize: 12, color: AppColors.textHint))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in items)
                  GestureDetector(
                    onTap: () => onPick(item.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selectedId == item.id ? AppColors.primary : AppColors.bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: selectedId == item.id ? AppColors.primary : AppColors.divider),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(item.emoji, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Text(item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight:
                                      selectedId == item.id ? FontWeight.bold : FontWeight.w500,
                                  color: selectedId == item.id ? Colors.white : AppColors.textMain)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

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
