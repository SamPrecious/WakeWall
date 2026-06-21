import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../controllers/wakewall_controller.dart';
import '../screens/crop_editor_screen.dart';
import '../screens/home_screen.dart';

part 'app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Screen,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: HomeRoute.page, initial: true),
    // The crop editor behaves like a temporary sheet over the home screen.
    CustomRoute(
      page: CropEditorRoute.page,
      transitionsBuilder: TransitionsBuilders.slideBottom,
      duration: Duration(milliseconds: 320),
      reverseDuration: Duration(milliseconds: 240),
      fullscreenDialog: true,
    ),
  ];
}
