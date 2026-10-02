// 历史页 —— 「穿搭日记」形态：月度穿搭日历 + 时间线列表
// 穿过的日子在日历上点亮（emoji 缩略），下方按时间轴回溯
// 第三阶段：真实模式从 /api/history 拉取，按真实日期点亮日历
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/mock_data.dart';
import '../theme/app_colors.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final int _month = 10; // 2026年10月（第三阶段接月份切换时改为可变）
  static const _weekLabels = ['一', '二', '三', '四', '五', '六', '日'];
  bool _loading = false;
  List<HistoryEntry> _history = MockData.history;

  @override
  void initState() {
    super.initState();
    if (!ApiClient.useMock) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _history = await ApiClient.getHistory();
    } catch (_) {
      // 拉取失败保留 mock 兜底，不让页面空白
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 该月第一天是周几（周一=0）。2026-10-01 = 周四 → 3
  int get _firstOffset {
    if (_month == 10) return 3;
    return 0;
  }

  int get _daysInMonth => _month == 10 ? 31 : 30;

  /// 已穿日映射：日 → emoji（只点亮当前展示月份，防跨月记录错亮到 10 月网格）
  Map<int, String> get _wornDays {
    final prefix = '2026-${_month.toString().padLeft(2, '0')}';
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        _header(),
        const SizedBox(height: 12),
        _calendar(),
        const SizedBox(height: 18),
        const Text('时间线',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        const SizedBox(height: 10),
        ..._history.map(_timelineCard),
      ],
    );
  }

  // ---- 头部：标题 + 月份切换 ----
  Widget _header() {
    return Row(
      children: [
        const Text('穿搭日记',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        const Spacer(),
        IconButton(
          onPressed: () {}, // 第二阶段仅当月
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textHint),
        ),
        Text('2026年$_month月',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMain)),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
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
              for (final w in _weekLabels)
                Expanded(
                  child: Center(
                    child: Text(w, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
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
              return Container(
                decoration: BoxDecoration(
                  color: emoji != null ? AppColors.primarySoft : AppColors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: emoji != null
                      ? Text(emoji, style: const TextStyle(fontSize: 18))
                      : Text('$day', style: const TextStyle(fontSize: 11.5, color: AppColors.textSub)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---- 时间线卡片：左轴 + emoji + 场合标签 + 洞察文案 + 评分 ----
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
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                ),
                Container(width: 1.5, color: AppColors.divider),
              ],
            ),
          ),
          Expanded(
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
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(e.occasionLabel,
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ),
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
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSub, height: 1.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
