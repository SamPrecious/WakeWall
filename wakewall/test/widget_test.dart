import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakewall/app.dart';
import 'package:wakewall/controllers/wakewall_controller.dart';
import 'package:wakewall/models/wallpaper.dart';
import 'package:wakewall/services/native_wallpaper_bridge.dart';
import 'package:wakewall/theme/wakewall_theme.dart';
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

    expect(find.text('Add Wallpapers'), findsNWidgets(2));
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Files & Other Apps'), findsOneWidget);
    expect(find.text('Always Use My Choice'), findsOneWidget);
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
    expect(find.text('Adding Wallpapers'), findsOneWidget);
    expect(find.text('0 of 2 processed'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    bridge.prepareFirstImage();
    await tester.pump();
    expect(find.text('1 of 2 processed'), findsOneWidget);

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

    expect(find.text('No Album'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Set Up WakeWall?'), findsOneWidget);
    expect(find.text('Not Now'), findsOneWidget);
    expect(find.text('Set Wallpaper'), findsOneWidget);

    await tester.tap(find.text('Set Wallpaper'));
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
    expect(find.text('In Order'), findsOneWidget);
    expect(find.text('Photo Source'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Fit mode'), findsNothing);
    expect(find.text('Backup'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Use WakeWall'), findsOneWidget);
    expect(find.text('Wake-event diagnostics'), findsNothing);
    expect(find.text('Wallpaper Scrolling'), findsOneWidget);
  });

  testWidgets('settings clearly reports when WakeWall is active', (
    tester,
  ) async {
    final controller = WakeWallController(bridge: _ActiveBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('WakeWall Is Active'), findsOneWidget);
    expect(find.text('Use WakeWall'), findsNothing);
  });

  testWidgets('theme setting defaults to system and can be changed', (
    tester,
  ) async {
    final bridge = _ThemeSettingsBridge();
    final controller = WakeWallController(bridge: bridge);
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    expect(controller.themeMode, WakeWallThemeMode.system);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, WakeWallThemeMode.light);
    expect(bridge.themeMode, 'light');

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, WakeWallThemeMode.dark);
    expect(bridge.themeMode, 'dark');
  });

  testWidgets('wallpaper scrolling stays off until its warning is accepted', (
    tester,
  ) async {
    final bridge = _ScrollingSettingsBridge();
    final controller = WakeWallController(bridge: bridge);
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    expect(controller.wallpaperScrolling, isFalse);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Wallpaper Scrolling'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();

    expect(find.text('Enable Wallpaper Scrolling?'), findsOneWidget);
    expect(controller.wallpaperScrolling, isFalse);
    expect(bridge.wallpaperScrolling, isFalse);

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(controller.wallpaperScrolling, isTrue);
    expect(bridge.wallpaperScrolling, isTrue);
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
    await tester.ensureVisible(find.text('Backup'));
    await tester.tap(find.text('Backup'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('backup-loading-overlay')), findsNothing);

    bridge.confirmLocation();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Creating Backup'), findsOneWidget);

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
    await tester.ensureVisible(find.text('Backup'));
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
    await tester.ensureVisible(find.text('Restore'));
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Replace Current Setup?'), findsOneWidget);
    expect(
      find.text(
        'Restoring a backup will replace your current wallpapers, order, crops, and settings.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Replace Current Setup?'), findsNothing);
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

    final strip = find.byKey(const ValueKey('wallpaper-strip-scroll'));
    expect(
      tester.getSize(strip).width,
      tester.getSize(find.byType(Scaffold)).width,
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('wallpaper-thumbnail-tidal')))
          .dx,
      closeTo(tester.getTopLeft(find.text('Up Next')).dx, 0.1),
    );
    expect(find.bySemanticsLabel('Tidal, wallpaper 1 of 4'), findsOneWidget);
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
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
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
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).hideCurrentSnackBar(reason: SnackBarClosedReason.timeout);
    await tester.pumpAndSettle();

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

  testWidgets('a removed wallpaper can be restored from the snackbar', (
    tester,
  ) async {
    final bridge = _PopulatedBridge();
    final controller = WakeWallController(bridge: bridge);
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('wallpaper-drag-0'))),
    );
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('wallpaper-remove-target'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Wallpaper removed'), findsOneWidget);
    expect(bridge.wallpapers.length, 3);
    final notice = tester.widget<SnackBar>(find.byType(SnackBar));
    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    expect(notice.duration, const Duration(milliseconds: 2800));
    expect(notice.width, 340);
    expect(notice.action?.textColor, scaffoldContext.wakeWallColors.tealStrong);
    expect(find.byIcon(Icons.delete_outline_rounded), findsWidgets);
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).hideCurrentSnackBar(reason: SnackBarClosedReason.action);
    await tester.pumpAndSettle();

    expect(bridge.wallpapers.length, 4);
    expect(bridge.wallpapers.first['sampleIndex'], 0);
    expect(bridge.finalizedRemoval, isFalse);
  });

  testWidgets('crop editor opens and accepts a pinch gesture', (tester) async {
    final controller = WakeWallController(bridge: _PopulatedBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Adjust Crop'));
    await tester.pumpAndSettle();

    expect(find.text('Adjust Wallpaper'), findsOneWidget);
    expect(find.text('Fill'), findsOneWidget);
    expect(find.text('Fit'), findsOneWidget);
    expect(find.text('Blur'), findsOneWidget);
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

    expect(find.byTooltip('Reset wallpaper'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('crop-editor-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Adjust Wallpaper'), findsNothing);
    expect(find.byTooltip('Adjust Crop'), findsOneWidget);
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
  Map<String, Object?>? removedWallpaper;
  bool finalizedRemoval = false;

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
    removedWallpaper = wallpapers.removeAt(index);
    return {
      ...await configuration(),
      'removedWallpaper': {
        'value': 'sample:$index',
        'index': index,
        'wasSelected': index == 0,
      },
    };
  }

  @override
  Future<Map<String, Object?>> restoreWallpaper({
    required String value,
    required int index,
    required bool wasSelected,
  }) async {
    wallpapers.insert(index, removedWallpaper!);
    removedWallpaper = null;
    return configuration();
  }

  @override
  Future<void> finalizeRemoval(String value) async {
    finalizedRemoval = true;
  }

  @override
  Future<Map<String, Object?>> moveWallpaper(int oldIndex, int newIndex) async {
    wallpapers.insert(newIndex, wallpapers.removeAt(oldIndex));
    return configuration();
  }
}

class _ActiveBridge extends _EmptyBridge {
  @override
  Future<Map<String, Object?>> configuration() async => {
    ...await super.configuration(),
    'wakeWallActive': true,
  };

  @override
  Future<Map<String, Object?>> state() => configuration();
}

class _ScrollingSettingsBridge extends _EmptyBridge {
  bool wallpaperScrolling = false;

  @override
  Future<void> updateSettings({
    required bool paused,
    required bool shuffle,
    required String fit,
    required String themeMode,
    required bool wallpaperScrolling,
  }) async {
    this.wallpaperScrolling = wallpaperScrolling;
  }
}

class _ThemeSettingsBridge extends _EmptyBridge {
  String themeMode = 'system';

  @override
  Future<void> updateSettings({
    required bool paused,
    required bool shuffle,
    required String fit,
    required String themeMode,
    required bool wallpaperScrolling,
  }) async {
    this.themeMode = themeMode;
  }
}

class _DelayedImportBridge extends _EmptyBridge {
  final Completer<Map<String, Object?>> importCompleter =
      Completer<Map<String, Object?>>();
  ValueChanged<ImportProgress>? importProgress;

  @override
  Future<Map<String, Object?>> configuration() async => {
    ...await super.configuration(),
    'photoSource': 'photos',
  };

  @override
  Future<Map<String, Object?>> pickImages() => importCompleter.future;

  @override
  void setImageImportProgressListener(ValueChanged<ImportProgress>? listener) {
    importProgress = listener;
  }

  void selectImages() {
    importProgress?.call(const ImportProgress(completed: 0, total: 2));
  }

  void prepareFirstImage() {
    importProgress?.call(const ImportProgress(completed: 1, total: 2));
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
  ValueChanged<ImportProgress>? importProgress;

  @override
  Future<Map<String, Object?>> configuration() async => {
    ...await super.configuration(),
    'photoSource': 'photos',
  };

  @override
  Future<Map<String, Object?>> pickImages() {
    importProgress?.call(const ImportProgress(completed: 0, total: 1));
    return configuration();
  }

  @override
  void setImageImportProgressListener(ValueChanged<ImportProgress>? listener) {
    importProgress = listener;
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
  Future<Map<String, Object?>> updateWallpaperAlbums(
    String value,
    Set<String> ids,
  ) => configuration();

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
