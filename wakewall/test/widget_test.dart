import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakewall/app.dart';
import 'package:wakewall/controllers/wakewall_controller.dart';
import 'package:wakewall/models/wallpaper.dart';
import 'package:wakewall/services/native_wallpaper_bridge.dart';
import 'package:wakewall/theme/wakewall_theme.dart';
import 'package:wakewall/widgets/abstract_wallpaper.dart';
import 'package:wakewall/widgets/privacy_policy_action.dart';

void main() {
  test('native action errors notify controller listeners', () async {
    final controller = WakeWallController(bridge: _PlatformFailureBridge());
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.openWallpaperPicker();

    expect(controller.lastNativeError, 'Test platform failure.');
    expect(notifications, 1);
  });

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

  testWidgets('startup never shows a false empty library', (tester) async {
    final bridge = _DelayedStartupBridge();
    final controller = WakeWallController(bridge: bridge);
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pump();
    await tester.pump();

    expect(find.text('Add Wallpapers'), findsNothing);
    expect(
      find.byKey(const ValueKey('initial-wallpaper-loading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('initial-wallpaper-strip')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('initial-loading-indicator')),
          )
          .opacity,
      0,
    );

    await tester.pump(const Duration(milliseconds: 280));
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.text('Loading Wallpapers'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('initial-loading-indicator')),
          )
          .opacity,
      1,
    );

    await bridge.finishLoading();
    await tester.pumpAndSettle();

    expect(find.text('Add Wallpapers'), findsNothing);
    expect(find.text('Up Next'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('initial-wallpaper-loading')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('initial-wallpaper-strip')), findsNothing);
    expect(tester.takeException(), isNull);
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
    expect(find.text('Midnight'), findsOneWidget);
    expect(find.text('Fit mode'), findsNothing);
    expect(find.text('Ultra High Resolution'), findsOneWidget);
    expect(find.textContaining('Experimental'), findsOneWidget);
    expect(find.text('Backup'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Use WakeWall'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('How WakeWall handles your data'), findsOneWidget);
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

  testWidgets('privacy policy footer is accessible and opens the exact URL', (
    tester,
  ) async {
    Uri? openedUri;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: WakeWallTheme.dark,
        home: Scaffold(
          body: PrivacyPolicyAction(
            launcher: (uri) async {
              openedUri = uri;
              return true;
            },
          ),
        ),
      ),
    );

    final action = find.byKey(const ValueKey('privacy-policy-action'));
    expect(action, findsOneWidget);
    final actionRect = tester.getRect(action);
    expect(actionRect.height, greaterThanOrEqualTo(68));
    expect(
      tester.getSemantics(action),
      matchesSemantics(
        isLink: true,
        label: 'Privacy Policy',
        value: 'How WakeWall handles your data',
        hint: 'Opens in your browser',
        textDirection: TextDirection.ltr,
      ),
    );

    // The trailing edge is part of the same full-row action, not icon-only UI.
    await tester.tapAt(Offset(actionRect.right - 8, actionRect.center.dy));
    await tester.pump();
    expect(openedUri.toString(), wakeWallPrivacyPolicyUrl);
    semantics.dispose();
  });

  testWidgets('privacy policy launch failure uses the WakeWall notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WakeWallTheme.midnight,
        home: Scaffold(body: PrivacyPolicyAction(launcher: (_) async => false)),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('privacy-policy-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(
      find.text('WakeWall couldn\'t open the privacy policy.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a switch card toggles the setting', (tester) async {
    final bridge = _ScrollingSettingsBridge();
    final controller = WakeWallController(bridge: bridge);
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause WakeWall'));
    await tester.pumpAndSettle();

    expect(controller.paused, isTrue);
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

    await tester.tap(find.text('Midnight'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, WakeWallThemeMode.midnight);
    expect(bridge.themeMode, 'midnight');
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
    await tester.tap(find.text('Wallpaper Scrolling'));
    await tester.pumpAndSettle();

    expect(find.text('Enable Wallpaper Scrolling?'), findsOneWidget);
    expect(controller.wallpaperScrolling, isFalse);
    expect(bridge.wallpaperScrolling, isFalse);

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(controller.wallpaperScrolling, isTrue);
    expect(bridge.wallpaperScrolling, isTrue);
  });

  testWidgets('ultra high resolution mode warns before enabling', (
    tester,
  ) async {
    final bridge = _ScrollingSettingsBridge();
    final controller = WakeWallController(bridge: bridge);
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    expect(controller.ultraHighResolutionMode, isFalse);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ultra High Resolution'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ultra High Resolution'));
    await tester.pumpAndSettle();

    expect(find.text('Enable Ultra High Resolution?'), findsOneWidget);
    expect(controller.ultraHighResolutionMode, isFalse);
    expect(bridge.ultraHighResolutionMode, isFalse);

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(controller.ultraHighResolutionMode, isTrue);
    expect(bridge.ultraHighResolutionMode, isTrue);
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
    expect(find.text('Add'), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);

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

  const responsiveViewports = [
    (name: 'phone', size: Size(412, 892), tablet: false),
    (name: 'compact tablet', size: Size(600, 960), tablet: true),
    (name: '7-inch tablet', size: Size(606, 1078), tablet: true),
    (name: '10-inch tablet', size: Size(823, 1463), tablet: true),
    (name: 'landscape tablet', size: Size(1280, 800), tablet: true),
  ];

  for (final viewport in responsiveViewports) {
    testWidgets('${viewport.name} home layout stays balanced', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = WakeWallController(bridge: _PopulatedBridge());

      await tester.pumpWidget(WakeWallApp(controller: controller));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final preview = tester.getRect(
        find.byKey(const ValueKey('wakewall-main-preview')),
      );
      final thumbnail = tester.getSize(
        find.byKey(const ValueKey('wallpaper-thumbnail-tidal')),
      );
      final expectedRatio =
          (math.min(viewport.size.width, viewport.size.height) /
                  math.max(viewport.size.width, viewport.size.height))
              .clamp(.44, .62);
      expect(preview.width / preview.height, closeTo(expectedRatio, .01));
      expect(thumbnail.height, greaterThan(thumbnail.width));

      if (!viewport.tablet) {
        expect(find.byKey(const ValueKey('tablet-home-content')), findsNothing);
        expect(preview.top, closeTo(60, .1));
        expect(preview.height, closeTo(672.4, 1));
        return;
      }

      final content = tester.getRect(
        find.byKey(const ValueKey('tablet-home-content')),
      );
      final topSpace = content.top;
      final bottomSpace = viewport.size.height - content.bottom;
      expect(topSpace, closeTo(bottomSpace, .1));
      expect(content.width, lessThanOrEqualTo(900));
      expect(preview.height, greaterThan(viewport.size.height * .40));
      if (viewport.size.height > viewport.size.width) {
        expect(preview.width, greaterThan(viewport.size.width * .68));
        expect(thumbnail.height, greaterThan(100));
      }
    });
  }

  testWidgets('tablet sheets and crop controls use readable widths', (
    tester,
  ) async {
    const viewport = Size(823, 1463);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = WakeWallController(bridge: _PopulatedBridge());

    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final settingsSheet = tester.getSize(
      find.byKey(const ValueKey('settings-sheet-content')),
    );
    expect(settingsSheet.width, lessThanOrEqualTo(680));
    expect(settingsSheet.width, greaterThan(500));
    await tester.ensureVisible(
      find.byKey(const ValueKey('privacy-policy-action')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Close Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Adjust Crop'));
    await tester.pumpAndSettle();

    final cropPreview = tester.getSize(
      find.byKey(const ValueKey('crop-editor-preview')),
    );
    final cropFooter = tester.getSize(
      find.byKey(const ValueKey('crop-editor-footer')),
    );
    final cancel = tester.getRect(
      find.byKey(const ValueKey('crop-editor-cancel')),
    );
    final save = tester.getRect(find.byKey(const ValueKey('crop-editor-save')));
    expect(cropPreview.width, lessThanOrEqualTo(620));
    expect(cropPreview.height, greaterThan(900));
    expect(cropFooter.width, lessThanOrEqualTo(680));
    expect(cancel.left, lessThan(20));
    expect(save.right, greaterThan(viewport.width - 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('short screens scroll instead of overflowing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = WakeWallController(bridge: _PopulatedBridge());

    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('short-screen-home-scroll')),
      findsOneWidget,
    );
    expect(find.text('WakeWall'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy policy remains reachable on short settings sheets', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = WakeWallController(bridge: _EmptyBridge());

    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    final action = find.byKey(const ValueKey('privacy-policy-action'));
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    final actionRect = tester.getRect(action);
    expect(actionRect.height, greaterThanOrEqualTo(68));
    expect(actionRect.top, greaterThanOrEqualTo(0));
    expect(actionRect.bottom, lessThanOrEqualTo(560));
    expect(tester.takeException(), isNull);
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

  testWidgets('damaged preview bytes show a clear fallback', (tester) async {
    final wallpaper = Wallpaper(
      id: 'damaged',
      name: 'Damaged',
      palette: const [Colors.black, Colors.black, Colors.white],
      style: 0,
      uri: 'local:damaged.jpg',
      thumbnail: Uint8List.fromList([0, 1, 2, 3]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 400,
          child: AbstractWallpaper(wallpaper: wallpaper),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('album management remains available through a long press', (
    tester,
  ) async {
    final controller = WakeWallController(bridge: _AlbumBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Albums'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Space'));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete Album'), findsOneWidget);
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
    final noticeMargin = notice.margin!.resolve(TextDirection.ltr);
    expect(notice.duration, const Duration(milliseconds: 2800));
    expect(notice.width, isNull);
    expect(noticeMargin.left, greaterThanOrEqualTo(28));
    expect(noticeMargin.right, greaterThanOrEqualTo(28));
    expect(noticeMargin.bottom, greaterThanOrEqualTo(28));
    expect(
      notice.padding,
      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    );
    expect(notice.dismissDirection, DismissDirection.down);
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
    expect(find.text('Pinch to zoom · Drag to position'), findsOneWidget);
    expect(find.byTooltip('Rotate wallpaper'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const ValueKey('crop-grid')))
          .opacity,
      0,
    );

    final center = tester.getCenter(
      find.text('Pinch to zoom · Drag to position'),
    );
    final firstFinger = await tester.createGesture(pointer: 1);
    final secondFinger = await tester.createGesture(pointer: 2);
    await firstFinger.down(center.translate(-40, -400));
    await secondFinger.down(center.translate(40, -400));
    await firstFinger.moveTo(center.translate(-90, -400));
    await secondFinger.moveTo(center.translate(90, -400));
    await tester.pump();
    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const ValueKey('crop-grid')))
          .opacity,
      1,
    );
    await firstFinger.up();
    await secondFinger.up();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const ValueKey('crop-grid')))
          .opacity,
      0,
    );

    expect(find.byTooltip('Reset wallpaper'), findsOneWidget);
    await tester.tap(find.byTooltip('Rotate wallpaper'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Reset wallpaper'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('crop-editor-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Adjust Wallpaper'), findsNothing);
    expect(find.byTooltip('Adjust Crop'), findsOneWidget);
  });

  testWidgets('a failed crop save stays open and explains the problem', (
    tester,
  ) async {
    final controller = WakeWallController(bridge: _CropFailureBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Adjust Crop'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('crop-editor-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Adjust Wallpaper'), findsOneWidget);
    expect(find.text('Crop save failed.'), findsOneWidget);
    expect(find.byKey(const ValueKey('crop-editor-saving')), findsNothing);
  });
}

class _EmptyBridge extends NativeWallpaperBridge {
  @override
  Future<Map<String, Object?>> state() async => {
    'index': 0,
    'wallpaperCount': 0,
    'paused': false,
    'shuffle': false,
    'fit': 'cropToFill',
  };

  @override
  Future<Map<String, Object?>> configuration() async => {
    'index': 0,
    'paused': false,
    'shuffle': false,
    'fit': 'cropToFill',
    'wallpapers': const [],
  };
}

class _PlatformFailureBridge extends _EmptyBridge {
  @override
  Future<void> openWallpaperPicker() {
    throw PlatformException(
      code: 'test_failure',
      message: 'Test platform failure.',
    );
  }
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

class _DelayedStartupBridge extends _PopulatedBridge {
  final Completer<Map<String, Object?>> configurationResult = Completer();

  @override
  Future<Map<String, Object?>> state() async => {
    'index': 0,
    'wallpaperCount': wallpapers.length,
    'paused': false,
    'shuffle': false,
    'fit': 'cropToFill',
  };

  @override
  Future<Map<String, Object?>> configuration() => configurationResult.future;

  Future<void> finishLoading() async {
    if (configurationResult.isCompleted) return;
    configurationResult.complete(await super.configuration());
  }
}

class _AlbumBridge extends _PopulatedBridge {
  @override
  Future<Map<String, Object?>> configuration() async => {
    ...await super.configuration(),
    'albums': const [
      {'id': 'space', 'name': 'Space'},
    ],
    'activeAlbumIds': const <String>[],
  };
}

class _CropFailureBridge extends _PopulatedBridge {
  @override
  Future<Map<String, Object?>> updateCrop({
    required int index,
    required double scale,
    required double offsetX,
    required double offsetY,
    required String displayMode,
    required int fitBackgroundColor,
    required int rotationQuarterTurns,
  }) {
    throw PlatformException(code: 'crop_failure', message: 'Crop save failed.');
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
  bool ultraHighResolutionMode = false;

  @override
  Future<void> updateSettings({
    required bool paused,
    required bool shuffle,
    required String fit,
    required String themeMode,
    required bool wallpaperScrolling,
    required bool ultraHighResolutionMode,
  }) async {
    this.wallpaperScrolling = wallpaperScrolling;
    this.ultraHighResolutionMode = ultraHighResolutionMode;
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
    required bool ultraHighResolutionMode,
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
