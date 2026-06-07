import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakewall/app.dart';
import 'package:wakewall/controllers/wakewall_controller.dart';
import 'package:wakewall/models/wallpaper.dart';
import 'package:wakewall/services/native_wallpaper_bridge.dart';
import 'package:wakewall/widgets/abstract_wallpaper.dart';

void main() {
  testWidgets('WakeWall starts with an empty collection', (tester) async {
    final controller = WakeWallController(bridge: _EmptyBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('WakeWall'), findsOneWidget);
    expect(find.text('Add Wallpapers'), findsOneWidget);
    expect(find.text('Choose images to begin.'), findsNothing);
    expect(find.byKey(const ValueKey('empty-add-wallpapers')), findsOneWidget);
    expect(find.text('Up Next'), findsNothing);
  });

  testWidgets('Add wallpapers offers Photos and Files sources', (tester) async {
    final controller = WakeWallController(bridge: _EmptyBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Wallpapers'));
    await tester.pumpAndSettle();

    expect(find.text('Add wallpapers'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Files & other apps'), findsOneWidget);
    expect(find.text('Always use my choice'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
  });

  testWidgets('image import shows a blocking loading overlay', (tester) async {
    final bridge = _DelayedImportBridge();
    final controller = WakeWallController(bridge: bridge);
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Wallpapers'));
    await tester.pump();

    expect(find.byKey(const ValueKey('import-loading-overlay')), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('import-loading-overlay')), findsNothing);

    bridge.selectImages();
    await tester.pump(const Duration(milliseconds: 349));
    expect(find.byKey(const ValueKey('import-loading-overlay')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(
      find.byKey(const ValueKey('import-loading-overlay')),
      findsOneWidget,
    );
    expect(find.text('Adding wallpapers'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    bridge.finishImport();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-loading-overlay')), findsNothing);
  });

  testWidgets('cancelling image selection never shows the loading overlay', (
    tester,
  ) async {
    final controller = WakeWallController(bridge: _CancelledImportBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Wallpapers'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('import-loading-overlay')), findsNothing);
  });

  testWidgets('quick image imports do not flash the loading overlay', (
    tester,
  ) async {
    final controller = WakeWallController(bridge: _QuickImportBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Wallpapers'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-loading-overlay')), findsNothing);
  });

  testWidgets('first successful import offers wallpaper setup', (tester) async {
    final bridge = _SetupPromptBridge();
    final controller = WakeWallController(bridge: bridge);
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Wallpapers'));
    await tester.pumpAndSettle();

    expect(find.text('Set up WakeWall?'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Set wallpaper'), findsOneWidget);

    await tester.tap(find.text('Set wallpaper'));
    await tester.pumpAndSettle();
    expect(bridge.openedWallpaperPicker, isTrue);
  });

  testWidgets('settings keeps the simple shuffle-first controls', (
    tester,
  ) async {
    final controller = WakeWallController(bridge: _EmptyBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('In order'), findsOneWidget);
    expect(find.text('Photo source'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Fit mode'), findsNothing);
    expect(find.text('Backup'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Use WakeWall'), findsOneWidget);
    expect(find.text('Wake-event diagnostics'), findsNothing);
  });

  testWidgets('backup progress waits until a save location is confirmed', (
    tester,
  ) async {
    final bridge = _DelayedBackupBridge();
    final controller = WakeWallController(bridge: bridge);
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('backup-loading-overlay')), findsNothing);

    bridge.confirmLocation();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Creating backup'), findsOneWidget);

    bridge.finishBackup();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('backup-loading-overlay')), findsNothing);
  });

  testWidgets('cancelling backup never shows progress', (tester) async {
    final controller = WakeWallController(bridge: _CancelledBackupBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('backup-loading-overlay')), findsNothing);
  });

  testWidgets('restore warns before replacing a populated setup', (
    tester,
  ) async {
    final bridge = _PopulatedBridge();
    final controller = WakeWallController(bridge: bridge);
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Replace current setup?'), findsOneWidget);
    expect(
      find.text(
        'Restoring a backup will replace your current wallpapers, order, crops, and settings.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Replace current setup?'), findsNothing);
  });

  testWidgets('WakeWall renders the populated home screen', (tester) async {
    final controller = WakeWallController(bridge: _PopulatedBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('WakeWall'), findsOneWidget);
    expect(find.text('Up Next'), findsOneWidget);
    expect(find.text('ADD'), findsOneWidget);

    final firstThumbnail = tester.getSize(
      find.byKey(const ValueKey('wallpaper-thumbnail-tidal')),
    );
    final secondThumbnail = tester.getSize(
      find.byKey(const ValueKey('wallpaper-thumbnail-silver')),
    );
    expect(firstThumbnail.height, greaterThan(firstThumbnail.width * 1.5));
    expect(firstThumbnail, secondThumbnail);
  });

  testWidgets('large preview keeps a complete landscape source available', (
    tester,
  ) async {
    final image = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final wallpaper = Wallpaper(
      id: 'group-photo',
      name: 'Group photo',
      palette: const [Colors.black, Colors.black, Colors.white],
      style: 0,
      uri: 'local:group-photo.jpg',
      thumbnail: image,
      imageWidth: 1600,
      imageHeight: 900,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 400,
            child: AbstractWallpaper(wallpaper: wallpaper, previewBytes: image),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('holding a wallpaper reveals the remove target', (tester) async {
    final controller = WakeWallController(bridge: _PopulatedBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('wallpaper-drag-0'))),
    );
    await tester.pump(const Duration(milliseconds: 650));

    final overlay = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('wallpaper-remove-overlay')),
    );
    expect(overlay.opacity, 1);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('wallpapers can be dragged to remove and reorder', (
    tester,
  ) async {
    final bridge = _PopulatedBridge();
    final controller = WakeWallController(bridge: bridge);
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    var gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('wallpaper-drag-0'))),
    );
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('wallpaper-remove-target'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(bridge.wallpapers.length, 3);

    final firstId = bridge.wallpapers.first['sampleIndex'];
    gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('wallpaper-drag-0'))),
    );
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('wallpaper-drag-2'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(bridge.wallpapers[2]['sampleIndex'], firstId);
  });

  testWidgets('crop editor opens and accepts a pinch gesture', (tester) async {
    final controller = WakeWallController(bridge: _PopulatedBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Adjust crop'));
    await tester.pumpAndSettle();

    expect(find.text('Adjust crop'), findsOneWidget);
    expect(find.text('Pinch to zoom | Drag to position'), findsOneWidget);

    final center = tester.getCenter(
      find.text('Pinch to zoom | Drag to position'),
    );
    final firstFinger = await tester.createGesture(pointer: 1);
    final secondFinger = await tester.createGesture(pointer: 2);
    await firstFinger.down(center.translate(-40, -400));
    await secondFinger.down(center.translate(40, -400));
    await firstFinger.moveTo(center.translate(-90, -400));
    await secondFinger.moveTo(center.translate(90, -400));
    await tester.pump();
    await firstFinger.up();
    await secondFinger.up();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Reset crop'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Adjust crop'), findsNothing);
    expect(find.byTooltip('Adjust crop'), findsOneWidget);
  });
}

class _EmptyBridge extends NativeWallpaperBridge {
  @override
  Future<Map<String, Object?>> configuration() async => {
    'index': 0,
    'paused': false,
    'shuffle': false,
    'fit': 'cropToFill',
    'wallpapers': const [],
  };
}

class _PopulatedBridge extends _EmptyBridge {
  final List<Map<String, Object?>> wallpapers = List.generate(
    4,
    (index) => {
      'sampleIndex': index,
      'crop': const {'scale': 1.0, 'offsetX': 0.0, 'offsetY': 0.0},
    },
  );

  @override
  Future<Map<String, Object?>> configuration() async => {
    'index': 0,
    'paused': false,
    'shuffle': false,
    'fit': 'cropToFill',
    'wallpapers': wallpapers,
  };

  @override
  Future<Map<String, Object?>> removeWallpaper(int index) async {
    wallpapers.removeAt(index);
    return configuration();
  }

  @override
  Future<Map<String, Object?>> moveWallpaper(int oldIndex, int newIndex) async {
    wallpapers.insert(newIndex, wallpapers.removeAt(oldIndex));
    return configuration();
  }
}

class _DelayedImportBridge extends _EmptyBridge {
  final Completer<Map<String, Object?>> importCompleter =
      Completer<Map<String, Object?>>();
  VoidCallback? importStarted;

  @override
  Future<Map<String, Object?>> configuration() async => {
    ...await super.configuration(),
    'photoSource': 'photos',
  };

  @override
  Future<Map<String, Object?>> pickImages() => importCompleter.future;

  @override
  void setImageImportStartedListener(VoidCallback? listener) {
    importStarted = listener;
  }

  void selectImages() {
    importStarted?.call();
  }

  void finishImport() {
    importCompleter.complete({
      'index': 0,
      'paused': false,
      'shuffle': false,
      'fit': 'cropToFill',
      'photoSource': 'photos',
      'wallpapers': const [],
    });
  }
}

class _QuickImportBridge extends _EmptyBridge {
  VoidCallback? importStarted;

  @override
  Future<Map<String, Object?>> configuration() async => {
    ...await super.configuration(),
    'photoSource': 'photos',
  };

  @override
  Future<Map<String, Object?>> pickImages() {
    importStarted?.call();
    return configuration();
  }

  @override
  void setImageImportStartedListener(VoidCallback? listener) {
    importStarted = listener;
  }
}

class _CancelledImportBridge extends _QuickImportBridge {
  @override
  Future<Map<String, Object?>> pickImages() async => {'cancelled': true};
}

class _SetupPromptBridge extends _EmptyBridge {
  bool openedWallpaperPicker = false;
  final List<Map<String, Object?>> wallpapers = [];

  @override
  Future<Map<String, Object?>> configuration() async => {
    ...await super.configuration(),
    'photoSource': 'photos',
    'wallpapers': wallpapers,
  };

  @override
  Future<Map<String, Object?>> pickImages() async {
    wallpapers.add({
      'sampleIndex': 0,
      'crop': const {'scale': 1.0, 'offsetX': 0.0, 'offsetY': 0.0},
    });
    return configuration();
  }

  @override
  Future<bool> claimWallpaperSetupOffer() async => true;

  @override
  Future<void> openWallpaperPicker() async {
    openedWallpaperPicker = true;
  }
}

class _DelayedBackupBridge extends _EmptyBridge {
  final Completer<Map<String, Object?>> backupCompleter =
      Completer<Map<String, Object?>>();
  VoidCallback? operationStarted;

  @override
  Future<Map<String, Object?>> backup() => backupCompleter.future;

  @override
  void setFileOperationStartedListener(VoidCallback? listener) {
    operationStarted = listener;
  }

  void confirmLocation() {
    operationStarted?.call();
  }

  void finishBackup() {
    backupCompleter.complete({'message': 'Backup saved.'});
  }
}

class _CancelledBackupBridge extends _DelayedBackupBridge {
  @override
  Future<Map<String, Object?>> backup() async => {'cancelled': true};
}
