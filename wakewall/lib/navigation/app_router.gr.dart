// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [CropEditorScreen]
class CropEditorRoute extends PageRouteInfo<CropEditorRouteArgs> {
  CropEditorRoute({
    required WakeWallController controller,
    required int wallpaperIndex,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         CropEditorRoute.name,
         args: CropEditorRouteArgs(
           controller: controller,
           wallpaperIndex: wallpaperIndex,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'CropEditorRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<CropEditorRouteArgs>();
      return CropEditorScreen(
        controller: args.controller,
        wallpaperIndex: args.wallpaperIndex,
        key: args.key,
      );
    },
  );
}

class CropEditorRouteArgs {
  const CropEditorRouteArgs({
    required this.controller,
    required this.wallpaperIndex,
    this.key,
  });

  final WakeWallController controller;

  final int wallpaperIndex;

  final Key? key;

  @override
  String toString() {
    return 'CropEditorRouteArgs{controller: $controller, wallpaperIndex: $wallpaperIndex, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CropEditorRouteArgs) return false;
    return controller == other.controller &&
        wallpaperIndex == other.wallpaperIndex &&
        key == other.key;
  }

  @override
  int get hashCode =>
      controller.hashCode ^ wallpaperIndex.hashCode ^ key.hashCode;
}

/// generated route for
/// [HomeScreen]
class HomeRoute extends PageRouteInfo<HomeRouteArgs> {
  HomeRoute({
    required WakeWallController controller,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         HomeRoute.name,
         args: HomeRouteArgs(controller: controller, key: key),
         initialChildren: children,
       );

  static const String name = 'HomeRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<HomeRouteArgs>();
      return HomeScreen(controller: args.controller, key: args.key);
    },
  );
}

class HomeRouteArgs {
  const HomeRouteArgs({required this.controller, this.key});

  final WakeWallController controller;

  final Key? key;

  @override
  String toString() {
    return 'HomeRouteArgs{controller: $controller, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HomeRouteArgs) return false;
    return controller == other.controller && key == other.key;
  }

  @override
  int get hashCode => controller.hashCode ^ key.hashCode;
}
