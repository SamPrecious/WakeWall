import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wakewall/controllers/wakewall_controller.dart';
import 'package:wakewall/models/wallpaper.dart';
import 'package:wakewall/services/native_wallpaper_bridge.dart';

void main() {
  test(
    'controller restores and updates the native current wallpaper',
    () async {
      final bridge = _FakeNativeWallpaperBridge(currentIndex: 2);
      final controller = WakeWallController(bridge: bridge);

      await controller.initialize();
      expect(controller.selectedIndex, 2);
      expect(controller.selectedPreview, bridge.previewBytes);

      await controller.select(1);
      expect(controller.selectedIndex, 1);
      expect(bridge.currentIndex, 1);
      expect(controller.selectedPreview, bridge.previewBytes);
    },
  );

  test('manual next follows the native shuffle result', () async {
    final bridge = _FakeNativeWallpaperBridge(currentIndex: 0, nextIndex: 3);
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    await controller.next();

    expect(controller.selectedIndex, 3);
  });

  test('lightweight resume refresh keeps the loaded image previews', () async {
    final bridge = _FakeNativeWallpaperBridge(currentIndex: 0);
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    bridge.currentIndex = 2;
    await controller.refreshState();

    expect(controller.selectedIndex, 2);
    expect(controller.wallpapers.length, 4);
    expect(controller.selectedPreview, bridge.previewBytes);
  });

  test('controller saves the preferred photo source', () async {
    final bridge = _FakeNativeWallpaperBridge(currentIndex: 0);
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    await controller.setPhotoSource(PhotoSource.files);

    expect(controller.photoSource, PhotoSource.files);
    expect(bridge.photoSource, 'files');
  });

  test('controller applies a restored backup configuration', () async {
    final bridge = _FakeNativeWallpaperBridge(currentIndex: 0);
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    final message = await controller.restore();

    expect(message, 'Backup restored.');
    expect(controller.selectedIndex, 1);
    expect(controller.order, RotationOrder.shuffle);
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

  test('controller appends incremental native import results', () async {
    final bridge = _IncrementalImportBridge(currentIndex: 0);
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    final initialCount = controller.wallpapers.length;
    await controller.addImages();

    expect(controller.wallpapers.length, initialCount + 1);
    expect(controller.wallpapers.last.name, 'Incremental photo.jpg');
  });

  test('controller automatically recovers a native import failure', () async {
    final bridge = _FakeNativeWallpaperBridge(
      currentIndex: 0,
      failedImageBytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    final initialCount = controller.wallpapers.length;
    await controller.addImages();

    expect(controller.wallpapers.length, initialCount + 1);
    expect(controller.lastNativeError, isNull);
  });

  test('controller reports imports that expose no readable bytes', () async {
    final bridge = _FakeNativeWallpaperBridge(
      currentIndex: 0,
      failedWithoutBytes: 1,
    );
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    await controller.addImages();

    expect(controller.lastNativeError, 'One photo could not be imported.');
  });
}

class _FakeNativeWallpaperBridge extends NativeWallpaperBridge {
  _FakeNativeWallpaperBridge({
    required this.currentIndex,
    this.nextIndex,
    this.failedImageBytes,
    this.failedWithoutBytes = 0,
  }) {
    wallpapers = List.generate(
      4,
      (index) => {
        'uri': 'content://wakewall/photo-$index',
        'name': 'Photo $index.jpg',
        'preview': previewBytes,
        'crop': const {'scale': 1.0, 'offsetX': 0.0, 'offsetY': 0.0},
      },
    );
  }

  int currentIndex;
  final int? nextIndex;
  final Uint8List? failedImageBytes;
  final int failedWithoutBytes;
  String photoSource = 'askEveryTime';
  final Uint8List previewBytes = Uint8List.fromList([1, 2, 3, 4]);
  late final List<Map<String, Object?>> wallpapers;

  @override
  Future<Map<String, Object?>> configuration() async => {
    'index': currentIndex,
    'paused': false,
    'shuffle': false,
    'fit': 'cropToFill',
    'photoSource': photoSource,
    'wallpapers': wallpapers,
  };

  @override
  Future<Map<String, Object?>> state() async => {
    'index': currentIndex,
    'paused': false,
    'shuffle': false,
    'fit': 'cropToFill',
    'photoSource': photoSource,
  };

  @override
  Future<Map<String, Object?>> pickImages() async {
    if (failedImageBytes != null || failedWithoutBytes > 0) {
      return {
        ...await configuration(),
        'failedImages': failedImageBytes == null
            ? <Object?>[]
            : [
                {'name': 'Recovered photo.png', 'bytes': failedImageBytes},
              ],
        'failedWithoutBytesCount': failedWithoutBytes,
      };
    }
    wallpapers.add({
      'uri': 'content://wakewall/my-photo',
      'name': 'My photo.jpg',
      'crop': const {'scale': 1.0, 'offsetX': 0.0, 'offsetY': 0.0},
    });
    return configuration();
  }

  @override
  Future<Map<String, Object?>> restore() async => {
    ...await configuration(),
    'index': 1,
    'shuffle': true,
    'message': 'Backup restored.',
  };

  @override
  Future<Map<String, Object?>> importNormalizedImages(
    List<Map<String, Object?>> images,
  ) async {
    for (final image in images) {
      wallpapers.add({
        'uri': 'content://wakewall/recovered-${wallpapers.length}',
        'name': image['name'],
        'crop': const {'scale': 1.0, 'offsetX': 0.0, 'offsetY': 0.0},
      });
    }
    return {
      ...await configuration(),
      'normalizedImportedCount': images.length,
      'normalizedFailedCount': 0,
    };
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

  @override
  Future<void> updatePhotoSource(String source) async {
    photoSource = source;
  }
}

class _IncrementalImportBridge extends _FakeNativeWallpaperBridge {
  _IncrementalImportBridge({required super.currentIndex});

  @override
  Future<Map<String, Object?>> pickImages() async => {
    'index': currentIndex,
    'paused': false,
    'shuffle': false,
    'fit': 'cropToFill',
    'photoSource': photoSource,
    'addedWallpapers': [
      {
        'uri': 'content://wakewall/incremental-photo',
        'name': 'Incremental photo.jpg',
        'crop': const {'scale': 1.0, 'offsetX': 0.0, 'offsetY': 0.0},
      },
    ],
  };
}
