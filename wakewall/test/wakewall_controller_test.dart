import 'package:flutter_test/flutter_test.dart';
import 'package:wakewall/controllers/wakewall_controller.dart';
import 'package:wakewall/services/native_wallpaper_bridge.dart';

void main() {
  test(
    'controller restores and updates the native current wallpaper',
    () async {
      final bridge = _FakeNativeWallpaperBridge(currentIndex: 2);
      final controller = WakeWallController(bridge: bridge);

      await controller.initialize();
      expect(controller.selectedIndex, 2);

      await controller.select(1);
      expect(controller.selectedIndex, 1);
      expect(bridge.currentIndex, 1);
    },
  );

  test('manual next follows the native shuffle result', () async {
    final bridge = _FakeNativeWallpaperBridge(currentIndex: 0, nextIndex: 3);
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    await controller.next();

    expect(controller.selectedIndex, 3);
  });

  test('controller adds and removes user images through Android', () async {
    final bridge = _FakeNativeWallpaperBridge(currentIndex: 0);
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    final initialCount = controller.wallpapers.length;
    await controller.addImages();
    expect(controller.wallpapers.last.isUserImage, isTrue);
    expect(controller.wallpapers.last.name, 'My photo.jpg');

    await controller.removeAt(controller.wallpapers.length - 1);
    expect(controller.wallpapers.length, initialCount);
    expect(
      controller.wallpapers.any(
        (wallpaper) => wallpaper.name == 'My photo.jpg',
      ),
      isFalse,
    );
  });
}

class _FakeNativeWallpaperBridge extends NativeWallpaperBridge {
  _FakeNativeWallpaperBridge({required this.currentIndex, this.nextIndex});

  int currentIndex;
  final int? nextIndex;
  final List<Map<String, Object?>> wallpapers = List.generate(
    4,
    (index) => {
      'uri': 'content://wakewall/photo-$index',
      'name': 'Photo $index.jpg',
      'crop': const {'scale': 1.0, 'offsetX': 0.0, 'offsetY': 0.0},
    },
  );

  @override
  Future<Map<String, Object?>> configuration() async => {
    'index': currentIndex,
    'paused': false,
    'shuffle': false,
    'fit': 'cropToFill',
    'wallpapers': wallpapers,
  };

  @override
  Future<Map<String, Object?>> pickImages() async {
    wallpapers.add({
      'uri': 'content://wakewall/my-photo',
      'name': 'My photo.jpg',
      'crop': const {'scale': 1.0, 'offsetX': 0.0, 'offsetY': 0.0},
    });
    return configuration();
  }

  @override
  Future<Map<String, Object?>> removeWallpaper(int index) async {
    wallpapers.removeAt(index);
    return configuration();
  }

  @override
  Future<int?> setCurrent(int index) async {
    currentIndex = index;
    return currentIndex;
  }

  @override
  Future<int?> showNext() async {
    currentIndex = nextIndex ?? currentIndex + 1;
    return currentIndex;
  }
}
