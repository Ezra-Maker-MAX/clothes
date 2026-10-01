// 顶部问候区：时间问候 + 情绪价值小字 + 圆形头像
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';

class GreetingHeader extends StatelessWidget {
  const GreetingHeader({super.key, required this.weather, required this.greeting, required this.tip});

  final WeatherInfo weather;
  final String greeting;
  final String tip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          // 左：问候文案
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${weather.condition} · ${weather.city}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSub,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  greeting,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMain,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tip,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSub),
                ),
              ],
            ),
          ),
          // 右：圆形头像
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF9C87C9), AppColors.primary],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x22715F9B),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text('👸', style: TextStyle(fontSize: 26)),
          ),
        ],
      ),
    );
  }
}
