// 历史页 —— 「穿搭日记」形态：月度穿搭日历 + 时间线列表
// 穿过的日子在日历上点亮（emoji 缩略），下方按时间轴回溯
// 第三阶段：真实模式从 /api/history 按月拉取（month=YYYY-MM，服务端已支持），
// 月份可切换（之前按钮是空实现——同类"点了没反应"问题，本版修复）。
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/mock_data.dart';
import '../theme/app_colors.dart';
import 'history_detail_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTime _month = DateTime.now(); // 展示的月份（取年月）
  bool _loading = false;
  String? _errorDetail;
  List<HistoryEntry> _history = MockData.history;

  bool get _real => !ApiClient.useMock;

  @override
  void initState() {
    super.initState();
    if (_real) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final m = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
      final list = await ApiClient.getHistory(month: m);
      if (mounted) {
        setState(() {
          _history = list;
          _errorDetail = null;
        });
      }
    } catch (e) {
      // 拉取失败保留 mock 兜底，不让页面空白
      if (mounted) setState(() => _errorDetail = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _shiftMonth(int delta) async {
    if (!_real) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('演示模式只有当月数据'),
            backgroundColor: AppColors.textMain,
            behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  /// 该月第一天是周几（周一=0）
  int get _firstOffset {
    final first = DateTime(_month.year, _month.month, 1);
    return first.weekday - 1; // Dart weekday：周一=1 ... 周日=7
  }

  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;

  /// 已穿日映射：日 → emoji（当前展示月已按服务端 month 过滤，双保险再判一次）
  Map<int, String> get _wornDays {
    final prefix =
        '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
    final m = <int, String>{};
    for (final e in _history) {
      if (!e.rawDate.startsWith(prefix)) continue;
      final day = int.tryParse(RegExp(r'(\d+)日').firstMatch(e.date)?.group(1) ?? '');
      if (day != null) m[day] = e.emoji;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _history.isEmpty) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _real ? _load : () async {},
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          _header(),
          const SizedBox(height: 12),
          _calendar(),
          const SizedBox(height: 18),
          Text('时间线',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
          const SizedBox(height: 10),
          if (!_real) ..._history.map(_timelineCard),
          if (_real && _history.isEmpty && !_loading)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppColors.radius),
                boxShadow: AppColors.softShadow,
              ),
              child: Column(
                children: [
                  const Text('🗓️', style: TextStyle(fontSize: 36)),
                  const SizedBox(height: 8),
                  Text('${_month.month} 月还没有穿搭记录',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                  const SizedBox(height: 4),
                  Text('去首页「就穿这套」记一天，日历就会亮起来',
                      style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                ],
              ),
            ),
          if (_real) ..._history.map(_timelineCard),
          if (_errorDetail != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('加载失败：$_errorDetail',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, color: AppColors.textHint)),
            ),
        ],
      ),
    );
  }

  // ---- 头部：标题 + 月份切换（真实可用，按月拉云端数据） ----
  Widget _header() {
    return Row(
      children: [
        Text('穿搭日记',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        const Spacer(),
        IconButton(
          onPressed: () => _shiftMonth(-1),
          icon: Icon(Icons.chevron_left_rounded, color: AppColors.textMain),
        ),
        Text('${_month.year}年${_month.month}月',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMain)),
        IconButton(
          onPressed: () => _shiftMonth(1),
          icon: Icon(Icons.chevron_right_rounded, color: AppColors.textMain),
        ),
      ],
    );
  }

  // ---- 月度穿搭日历：7 列网格，穿过的日子点亮 ----
  Widget _calendar() {
    final worn = _wornDays;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          // 星期行
          Row(
            children: [
              for (final w in const ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Center(
                    child: Text(w, style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 日期格
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
            ),
            itemCount: _firstOffset + _daysInMonth,
            itemBuilder: (_, i) {
              if (i < _firstOffset) return const SizedBox.shrink();
              final day = i - _firstOffset + 1;
              final emoji = worn[day];
              final isToday = _month.year == DateTime.now().year &&
                  _month.month == DateTime.now().month &&
                  day == DateTime.now().day;
              return Container(
                decoration: BoxDecoration(
                  color: emoji != null
                      ? AppColors.primarySoft
                      : isToday
                          ? AppColors.bg
                          : AppColors.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: isToday ? Border.all(color: AppColors.primary, width: 1.2) : null,
                ),
                child: Center(
                  child: emoji != null
                      ? Text(emoji, style: const TextStyle(fontSize: 18))
                      : Text('$day', style: TextStyle(fontSize: 11.5, color: AppColors.textSub)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---- 时间线卡片：左轴 + emoji + 场合标签 + 洞察文案 + 评分（点击进详情） ----
  Widget _timelineCard(HistoryEntry e) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧日期轴
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                ),
                Container(width: 1.5, color: AppColors.divider),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _openDetail(e),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12, left: 6),
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
                      children: [
                        Text(e.emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        Text(e.date,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(e.occasionLabel,
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ),
                        // 写了日记就挂个小标记，省得翻进去才发现
                        if (e.notes.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.edit_note_rounded, size: 15, color: AppColors.accent),
                        ],
                        const Spacer(),
                        // 满意度
                        ...List.generate(5, (s) {
                          return Icon(
                            s < e.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                            size: 13,
                            color: s < e.rating ? AppColors.accent : AppColors.divider,
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(e.summary,
                        style: TextStyle(fontSize: 12.5, color: AppColors.textSub, height: 1.5)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          e.notes.isNotEmpty ? '查看详情 · 日记' : '查看详情',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 15, color: AppColors.primary),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 进详情页：写日记 / 改星级都发生在那里，回来后刷新让标记立刻生效
  Future<void> _openDetail(HistoryEntry e) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HistoryDetailPage(entry: e)),
    );
    if (_real && mounted) _load();
  }
}
