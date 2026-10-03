// 穿搭日记详情页 —— 把"那天穿了什么"完整复原，并让用户写点自己的话
//
// 为什么有这一页：时间线只有一行摘要，看不到当时的天气、理由、妆容，
// 也没地方写"今天这身上班被夸了"这类只属于她的记忆。
//
// 能力：
//   · 单品大图横滑（服务端 join 出的当日单品图，旧记录无图则回落配色块）
//   · 当日天气 / 场合 / 推荐理由 / 妆容存档
//   · 星级可改（1~5 星，即时保存）
//   · 穿搭日记自由编辑 + 保存（PATCH /api/history → outfit_history.notes）
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../theme/app_colors.dart';

class HistoryDetailPage extends StatefulWidget {
  const HistoryDetailPage({super.key, required this.entry});

  final HistoryEntry entry;

  @override
  State<HistoryDetailPage> createState() => _HistoryDetailPageState();
}

class _HistoryDetailPageState extends State<HistoryDetailPage> {
  late final TextEditingController _notesCtrl = TextEditingController(text: widget.entry.notes);
  late final TextEditingController _nameCtrl = TextEditingController(text: widget.entry.outfitName);
  late int _rating = widget.entry.rating;
  late int _page = 0;

  bool _saving = false;
  bool _dirty = false;

  HistoryEntry get e => widget.entry;

  @override
  void dispose() {
    _notesCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// 保存日记 / 星级 / 搭配名
  Future<void> _save({int? rating, bool silent = false}) async {
    if (e.id.isEmpty) {
      _snack('这条记录没有可编辑的编号（演示数据），先记一次真实穿搭吧');
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.updateHistory(
        id: e.id,
        notes: _notesCtrl.text.trim(),
        rating: rating ?? _rating,
        outfitName: _nameCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _rating = rating ?? _rating;
        _dirty = false;
      });
      if (!silent) _snack('记下了 ✍️');
    } catch (err) {
      if (mounted) {
        var msg = err.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        if (msg.length > 60) msg = '${msg.substring(0, 60)}…';
        _snack('没存上：$msg');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: AppColors.textMain,
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final items = e.items;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textMain),
        ),
        title: Text('${e.date} · ${e.occasionLabel}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _gallery(items),
          const SizedBox(height: 16),
          _metaRow(items),
          const SizedBox(height: 14),
          if (e.reason.isNotEmpty) ...[
            _card('那天为什么这么搭', e.reason, icon: Icons.auto_awesome_rounded),
            const SizedBox(height: 12),
          ],
          if (e.makeup.isNotEmpty) ...[
            _card('妆容', e.makeup, icon: Icons.face_rounded),
            const SizedBox(height: 12),
          ],
          _diaryCard(),
          const SizedBox(height: 12),
          _ratingCard(),
        ],
      ),
    );
  }

  // ---- 单品大图横滑 ----
  Widget _gallery(List<HistoryItemBrief> items) {
    if (items.isEmpty) return _placeholder();
    return SizedBox(
      height: 260,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppColors.radius),
        child: Stack(
          children: [
            PageView.builder(
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final it = items[i];
                if (it.imageUrl.isEmpty) return _colorBlock(it);
                return Image.network(
                  it.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _colorBlock(it),
                );
              },
            ),
            // 底部渐变 + 单品名
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 26, 14, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(items[_page].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    if (items.length > 1)
                      Text('${_page + 1}/${items.length}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 无图（旧记录 / 图挂了）：用莫兰迪配色块 + 首字，不留空白
  Widget _placeholder() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppColors.radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.itemTop, AppColors.itemBottom],
        ),
      ),
      alignment: Alignment.center,
      child: Text(e.emoji, style: const TextStyle(fontSize: 84)),
    );
  }

  Widget _colorBlock(HistoryItemBrief it) {
    return Container(
      color: AppColors.itemTop,
      alignment: Alignment.center,
      child: Text(
        it.name.isEmpty ? '👗' : it.name.characters.first,
        style: TextStyle(fontSize: 64, color: AppColors.primary, fontWeight: FontWeight.w300),
      ),
    );
  }

  // ---- 天气 / 场合 / 来源 ----
  Widget _metaRow(List<HistoryItemBrief> items) {
    final bits = <String>[
      if (e.tempC != null) '${e.tempC}°',
      if (e.condition.isNotEmpty) e.condition,
      if (e.city.isNotEmpty) e.city,
    ];
    return Row(
      children: [
        if (bits.isNotEmpty)
          Expanded(child: _chip(Icons.thermostat_rounded, bits.join(' · '), AppColors.accentSoft, AppColors.accent)),
        if (bits.isNotEmpty && items.isNotEmpty) const SizedBox(width: 8),
        if (items.isNotEmpty)
          Expanded(
            child: _chip(
              e.source == 'manual' ? Icons.brush_rounded : Icons.auto_awesome_rounded,
              e.source == 'manual' ? '自己配的' : 'AI 推荐',
              AppColors.primarySoft,
              AppColors.primary,
            ),
          ),
      ],
    );
  }

  Widget _chip(IconData icon, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, String body, {required IconData icon}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(fontSize: 13, color: AppColors.textSub, height: 1.6)),
        ],
      ),
    );
  }

  // ---- 穿搭日记（可编辑） ----
  Widget _diaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('穿搭日记',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
              const Spacer(),
              if (_saving)
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              else if (_dirty)
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('保存', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameCtrl,
            onChanged: (_) => _markDirty(),
            style: TextStyle(fontSize: 13, color: AppColors.textMain),
            decoration: InputDecoration(
              hintText: '给这套起个名字（可留空）：如「被夸了的一天」',
              hintStyle: TextStyle(fontSize: 12, color: AppColors.textHint),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: AppColors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            onChanged: (_) => _markDirty(),
            maxLines: 6,
            minLines: 4,
            maxLength: 2000,
            style: TextStyle(fontSize: 13, color: AppColors.textMain, height: 1.6),
            decoration: InputDecoration(
              hintText: '今天这身怎么样？'
                  '\n· 舒服/难穿\n· 哪里被夸了\n· 下次想换成什么',
              hintStyle: TextStyle(fontSize: 12.5, color: AppColors.textHint, height: 1.6),
              filled: true,
              fillColor: AppColors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (e.notes.isEmpty && !_dirty)
            Text('留空也没关系，写一句给自己看的东西就行。',
                style: TextStyle(fontSize: 11, color: AppColors.textHint)),
        ],
      ),
    );
  }

  // ---- 星级（点一下即存） ----
  Widget _ratingCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          Text('今天穿得怎么样',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
          const Spacer(),
          ...List.generate(5, (i) {
            final on = i < _rating;
            return IconButton(
              onPressed: () => _save(rating: i + 1),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 1),
              constraints: const BoxConstraints(),
              icon: Icon(
                on ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 22,
                color: on ? AppColors.accent : AppColors.divider,
              ),
            );
          }),
        ],
      ),
    );
  }
}
