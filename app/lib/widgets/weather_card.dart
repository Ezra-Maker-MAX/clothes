// 天气卡片：左（天气图标 + 温度 / 体感）· 右（暖色体感标签）
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';

class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key, required this.weather});

  final WeatherInfo weather;

  IconData get _icon => switch (weather.condition) {
        '晴' => Icons.wb_sunny_rounded,
        '小雨' || '中雨' || '大雨' => Icons.umbrella_rounded,
        _ => Icons.cloud_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          // 左：图标 + 温度
          Icon(_icon, size: 40, color: AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${weather.tempC}',
                        style: TextStyle(
                            fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                    Text('°C',
                        style: TextStyle(fontSize: 15, color: AppColors.textSub, height: 2.2)),
                  ],
                ),
                Text('体感温度 ${weather.feelsLike}°C · ${weather.condition}',
                    style: TextStyle(fontSize: 13, color: AppColors.textSub)),
              ],
            ),
          ),
          // 右：暖色体感标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              weather.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
