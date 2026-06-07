import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'controllers/wakewall_controller.dart';
import 'navigation/app_router.dart';
import 'theme/wakewall_theme.dart';

class WakeWallApp extends StatefulWidget {
  const WakeWallApp({this.controller, super.key});

  final WakeWallController? controller;

  @override
  State<WakeWallApp> createState() => _WakeWallAppState();
}

class _WakeWallAppState extends State<WakeWallApp> with WidgetsBindingObserver {
  late final WakeWallController controller;
  late final AppRouter router;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller = widget.controller ?? WakeWallController();
    controller.initialize();
    router = AppRouter();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  // Refreshes the controls after returning from Android's wallpaper screens.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.refreshState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'WakeWall',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: WakeWallTheme.dark,
      routerConfig: router.config(
        deepLinkBuilder: (_) => DeepLink([HomeRoute(controller: controller)]),
      ),
    );
  }
}
