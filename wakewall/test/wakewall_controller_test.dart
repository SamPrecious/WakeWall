import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
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

  test('controller deduplicates lazy main and editor preview loads', () async {
    final bridge = _LazyPreviewBridge();
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    expect(controller.wallpapers[1].mainPreview, isNull);
    expect(controller.wallpapers[1].preview, isNull);

    final firstMainLoad = controller.ensureMainPreview(1);
    final duplicateMainLoad = controller.ensureMainPreview(1);
    expect(bridge.mainPreviewRequests, 1);
    bridge.mainPreviewResult.complete(bridge.mainBytes);
    await Future.wait([firstMainLoad, duplicateMainLoad]);
    expect(controller.wallpapers[1].mainPreview, same(bridge.mainBytes));

    final firstEditorLoad = controller.ensureEditorPreview(1);
    final duplicateEditorLoad = controller.ensureEditorPreview(1);
    expect(bridge.editorPreviewRequests, 1);
    bridge.editorPreviewResult.complete(bridge.editorBytes);
    await Future.wait([firstEditorLoad, duplicateEditorLoad]);
    expect(controller.wallpapers[1].preview, same(bridge.editorBytes));
  });

  test(
    'full native refresh preserves previews omitted from compact maps',
    () async {
      final bridge = _LazyPreviewBridge();
      final controller = WakeWallController(bridge: bridge);

      await controller.initialize();
      final mainLoad = controller.ensureMainPreview(1);
      final editorLoad = controller.ensureEditorPreview(1);
      bridge.mainPreviewResult.complete(bridge.mainBytes);
      bridge.editorPreviewResult.complete(bridge.editorBytes);
      await Future.wait([mainLoad, editorLoad]);

      await controller.initialize();

      expect(controller.wallpapers[1].thumbnail, same(bridge.secondThumbnail));
      expect(controller.wallpapers[1].mainPreview, same(bridge.mainBytes));
      expect(controller.wallpapers[1].preview, same(bridge.editorBytes));
    },
  );

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

  test('partial state refresh preserves settings it did not receive', () async {
    final controller = WakeWallController(bridge: _PartialStateBridge());

    await controller.initialize();
    await controller.refreshState();

    expect(controller.order, RotationOrder.shuffle);
    expect(controller.photoSource, PhotoSource.files);
    expect(controller.selectedIndex, 1);
  });

  test('controller skips malformed native wallpaper entries', () async {
    final controller = WakeWallController(bridge: _MalformedBridge());

    await controller.initialize();

    expect(controller.wallpapers.length, 1);
    expect(controller.wallpapers.single.name, 'Usable');
    expect(controller.wallpapers.single.crop.isDefault, isTrue);
  });

  test('controller saves the preferred photo source', () async {
    final bridge = _FakeNativeWallpaperBridge(currentIndex: 0);
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    await controller.setPhotoSource(PhotoSource.files);

    expect(controller.photoSource, PhotoSource.files);
    expect(bridge.photoSource, 'files');
  });

  test('controller applies album filters and wallpaper memberships', () async {
    final bridge = _AlbumBridge();
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    await controller.setActiveAlbums({'dogs', 'nature'});
    await controller.updateWallpaperAlbums(controller.wallpapers.first, {
      'dogs',
    });
    await controller.setImportAlbumPreference(false, {'dogs'});

    expect(controller.activeAlbumIds, {'dogs', 'nature'});
    expect(controller.wallpapers.first.albumIds, {'dogs'});
    expect(controller.albums.map((album) => album.name), ['Dogs', 'Nature']);
    expect(controller.askAlbumsAfterImport, isFalse);
    expect(controller.defaultImportAlbumIds, {'dogs'});
  });

  test(
    'imported wallpapers switch to all when outside the current view',
    () async {
      final bridge = _AlbumBridge();
      final controller = WakeWallController(bridge: bridge);

      await controller.initialize();
      await controller.setActiveAlbums({'dogs'});
      await controller.revealImportedAlbumSelection({'nature'});

      expect(controller.activeAlbumIds, isEmpty);

      await controller.setActiveAlbums({'dogs', 'nature'});
      await controller.revealImportedAlbumSelection({'nature'});

      expect(controller.activeAlbumIds, {'dogs', 'nature'});

      await controller.setActiveAlbums({});
      await controller.revealImportedAlbumSelection({'nature'});
      expect(controller.activeAlbumIds, isEmpty);

      await controller.setActiveAlbums({'dogs'});
      await controller.revealImportedAlbumSelection({});

      expect(controller.activeAlbumIds, isEmpty);
    },
  );

  test('saving a crop replaces its baked UI previews', () async {
    final bridge = _FakeNativeWallpaperBridge(currentIndex: 0);
    final controller = WakeWallController(bridge: bridge);

    await controller.initialize();
    final saved = await controller.updateCrop(
      0,
      const WallpaperCrop(scale: 1.5, offsetX: .1, offsetY: -.1),
      displayMode: WallpaperDisplayMode.blur,
      fitBackgroundColor: const Color(0xFF182230),
    );

    expect(saved, isTrue);
    expect(controller.wallpapers.first.crop.scale, 1.5);
    expect(controller.wallpapers.first.displayMode, WallpaperDisplayMode.blur);
    expect(
      controller.wallpapers.first.fitBackgroundColor,
      const Color(0xFF182230),
    );
    expect(controller.wallpapers.first.mainPreview, bridge.croppedPreviewBytes);
    expect(controller.wallpapers.first.thumbnail, bridge.croppedThumbnailBytes);
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
  final Uint8List croppedPreviewBytes = Uint8List.fromList([5, 6, 7, 8]);
  final Uint8List croppedThumbnailBytes = Uint8List.fromList([9, 10]);
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

  @override
  Future<Map<String, Object?>> updateCrop({
    required int index,
    required double scale,
    required double offsetX,
    required double offsetY,
    required String displayMode,
    required int fitBackgroundColor,
    required int rotationQuarterTurns,
  }) async => {
    ...wallpapers[index],
    'mainPreview': croppedPreviewBytes,
    'thumbnail': croppedThumbnailBytes,
    'crop': {'scale': scale, 'offsetX': offsetX, 'offsetY': offsetY},
    'displayMode': displayMode,
    'fitBackgroundColor': fitBackgroundColor,
  };
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

class _LazyPreviewBridge extends NativeWallpaperBridge {
  final Uint8List firstMain = Uint8List.fromList([1, 2, 3]);
  final Uint8List secondThumbnail = Uint8List.fromList([4, 5, 6]);
  final Uint8List mainBytes = Uint8List.fromList([7, 8, 9]);
  final Uint8List editorBytes = Uint8List.fromList([10, 11, 12]);
  final Completer<Uint8List?> mainPreviewResult = Completer();
  final Completer<Uint8List?> editorPreviewResult = Completer();
  int mainPreviewRequests = 0;
  int editorPreviewRequests = 0;

  @override
  Future<Map<String, Object?>> state() async => {
    'index': 0,
    'wallpaperCount': 2,
    'paused': false,
    'shuffle': false,
    'fit': 'cropToFill',
  };

  @override
  Future<Map<String, Object?>> configuration() async => {
    ...await state(),
    'wallpapers': [
      {
        'uri': 'local:first.jpg',
        'name': 'First',
        'mainPreview': firstMain,
        'crop': const {'scale': 1.0, 'offsetX': 0.0, 'offsetY': 0.0},
      },
      {
        'uri': 'local:second.jpg',
        'name': 'Second',
        'thumbnail': secondThumbnail,
        'crop': const {'scale': 1.0, 'offsetX': 0.0, 'offsetY': 0.0},
      },
    ],
  };

  @override
  Future<Uint8List?> mainPreview(String value) {
    mainPreviewRequests++;
    return mainPreviewResult.future;
  }

  @override
  Future<Uint8List?> editorPreview(String value) {
    editorPreviewRequests++;
    return editorPreviewResult.future;
  }
}

class _AlbumBridge extends _FakeNativeWallpaperBridge {
  _AlbumBridge() : super(currentIndex: 0);

  Set<String> activeIds = {};
  bool askAfterImport = true;
  Set<String> defaultIds = {};

  @override
  Future<Map<String, Object?>> configuration() async => {
    ...await super.configuration(),
    'albums': const [
      {'id': 'dogs', 'name': 'Dogs'},
      {'id': 'nature', 'name': 'Nature'},
    ],
    'activeAlbumIds': activeIds.toList(),
    'askAlbumsAfterImport': askAfterImport,
    'defaultImportAlbumIds': defaultIds.toList(),
  };

  @override
  Future<Map<String, Object?>> setActiveAlbums(Set<String> ids) async {
    activeIds = ids;
    return configuration();
  }

  @override
  Future<Map<String, Object?>> updateWallpaperAlbums(
    String value,
    Set<String> ids,
  ) async {
    final wallpaper = wallpapers.firstWhere((item) => item['uri'] == value);
    wallpaper['albumIds'] = ids.toList();
    return configuration();
  }

  @override
  Future<Map<String, Object?>> updateImportAlbumPreference(
    bool ask,
    Set<String> ids,
  ) async {
    askAfterImport = ask;
    defaultIds = ids;
    return configuration();
  }
}

class _PartialStateBridge extends _FakeNativeWallpaperBridge {
  _PartialStateBridge() : super(currentIndex: 0);

  @override
  Future<Map<String, Object?>> configuration() async => {
    ...await super.configuration(),
    'shuffle': true,
    'photoSource': 'files',
  };

  @override
  Future<Map<String, Object?>> state() async => {'index': 1};
}

class _MalformedBridge extends NativeWallpaperBridge {
  @override
  Future<Map<String, Object?>> configuration() async => {
    'index': 0,
    'wallpapers': [
      null,
      const <String, Object?>{},
      {'uri': 'local:usable.jpg', 'name': 'Usable'},
    ],
  };
}
