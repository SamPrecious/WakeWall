import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'controllers/wakewall_controller.dart';
import 'models/wallpaper.dart';
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
    // Tests may pass in a controller, but the real app owns the native-backed one.
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
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'WakeWall',
          debugShowCheckedModeBanner: false,
          themeMode: switch (controller.themeMode) {
            WakeWallThemeMode.system => ThemeMode.system,
            WakeWallThemeMode.light => ThemeMode.light,
            WakeWallThemeMode.dark => ThemeMode.dark,
            WakeWallThemeMode.midnight => ThemeMode.dark,
          },
          theme: WakeWallTheme.light,
          // Midnight is a dark theme variant, so Flutter still treats it as dark mode.
          darkTheme: controller.themeMode == WakeWallThemeMode.midnight
              ? WakeWallTheme.midnight
              : WakeWallTheme.dark,
          routerConfig: router.config(
            deepLinkBuilder: (_) =>
                DeepLink([HomeRoute(controller: controller)]),
          ),
        );
      },
    );
  }
}
