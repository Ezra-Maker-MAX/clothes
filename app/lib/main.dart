// App 入口：「搭配测试」
// 主题：米白底 + 莫兰迪紫主色 + 蜜桃橙强调；四 tab 外壳（IndexedStack 保持各页状态）
// 私密模式：解锁后整树重建为暗夜酒红色系（PrivateModeService.unlocked 驱动）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'pages/outfit_page.dart';
import 'pages/wardrobe_page.dart';
import 'services/private_body_store.dart';
import 'services/private_mode_service.dart';
import 'theme/app_colors.dart';
import 'widgets/nav_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PrivateModeService.init(); // 恢复 24h 内的私密模式解锁状态（不阻塞启动）
  PrivateBodyStore.init(); // 缓存私密身体数据（试衣间同步读取）
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const DapeiApp());
}

class DapeiApp extends StatelessWidget {
  const DapeiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听私密模式解锁状态：一变就重建 MaterialApp，全 App 换色
    return ValueListenableBuilder<bool>(
      valueListenable: PrivateModeService.unlocked,
      builder: (context, _, __) => MaterialApp(
        title: '衣念',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
            brightness: AppColors.privateMode ? Brightness.dark : Brightness.light,
          ),
          fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei'],
        ),
        home: const MainShell(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _pages = [HomePage(), WardrobePage(), OutfitPage(), HistoryPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: NavBar(index: _index, onTap: (i) => setState(() => _index = i)),
    );
  }
}
