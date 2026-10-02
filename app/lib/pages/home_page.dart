// 首页：问候区 → 天气卡片 → 今日推荐 → 统计卡片
// 第三阶段：真实模式从 /api/recommend + /api/history + /api/wardrobe 取数，
// 并带 loading / error 两种状态，文案遵循「嘴快心细、不油腻」的调性。
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/mock_data.dart';
import '../theme/app_colors.dart';
import '../widgets/greeting_header.dart';
import '../widgets/recommend_card.dart';
import '../widgets/stats_row.dart';
import '../widgets/weather_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  OutfitRecommendation _outfit = MockData.outfitA; // 占位，真实模式立即被 _load 替换
  HomeStats _stats = MockData.stats;
  bool _swapping = false;
  bool _loading = false;
  String? _error;
  String? _errorDetail; // 真实异常信息（小字展示，便于远程诊断网络问题）

  @override
  void initState() {
    super.initState();
    if (ApiClient.useMock) {
      _outfit = MockData.outfitA;
      _stats = MockData.stats;
    } else {
      _load();
    }
  }

  /// 拉取今日推荐 + 首页统计（真实模式）
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.getRecommendation(),
        ApiClient.getStats(),
      ]);
      if (mounted) {
        setState(() {
          _outfit = results[0] as OutfitRecommendation;
          _stats = results[1] as HomeStats;
          _error = null;
          _errorDetail = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '今天挑衣的服务打了个小盹，点一下再试';
          _errorDetail = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 「换一套」：调 ApiClient（mock 模式在备选池轮换，带 600ms 延迟手感）
  Future<void> _swap() async {
    setState(() => _swapping = true);
    try {
      final next = await ApiClient.getRecommendation(refresh: true);
      if (mounted) setState(() => _outfit = next);
    } catch (_) {
      _toast('换不动了，网络开了点小差，待会儿再试');
    } finally {
      if (mounted) setState(() => _swapping = false);
    }
  }

  /// 「就穿这套」：写历史 + 更新排重字段（真实模式落库，并刷新本月统计）
  Future<void> _accept() async {
    try {
      await ApiClient.acceptOutfit(_outfit);
      if (!ApiClient.useMock) {
        final s = await ApiClient.getStats();
        if (mounted) setState(() => _stats = s);
      } else {
        if (mounted) {
          setState(() => _stats = HomeStats(
            wardrobeItems: _stats.wardrobeItems,
            monthOutfits: _stats.monthOutfits + 1,
            neverWorn: _stats.neverWorn,
          ));
        }
      }
      _toast('已记入今日穿搭。这身不显腰，但只要你一走路，它就会出卖你。');
    } catch (_) {
      _toast('记不进去，网络开了点小差，待会儿再点');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        backgroundColor: AppColors.textMain,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // 加载态：给一句有调性的引导，而不是干巴巴的转圈
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 14),
            Text('正在为你挑今天的那一身…',
                style: TextStyle(color: AppColors.textSub, fontSize: 13)),
          ],
        ),
      );
    }

    // 错误态：解释为「服务打了个盹」，并给出明确的重试动作
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🪞', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.textMain, fontSize: 14),
                  textAlign: TextAlign.center),
            ),
            if (_errorDetail != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(_errorDetail!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSub, fontSize: 11),
                    textAlign: TextAlign.center),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('再试一次'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        GreetingHeader(
          weather: _outfit.weather,
          greeting: MockData.greeting(now),
          tip: MockData.greetingTip(now),
        ),
        const SizedBox(height: 16),
        WeatherCard(weather: _outfit.weather),
        const SizedBox(height: 14),
        RecommendCard(
          outfit: _outfit,
          swapping: _swapping,
          onSwap: _swap,
          onAccept: _accept,
        ),
        const SizedBox(height: 14),
        StatsRow(stats: _stats),
      ],
    );
  }
}
