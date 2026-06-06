import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakewall/app.dart';
import 'package:wakewall/controllers/wakewall_controller.dart';
import 'package:wakewall/services/native_wallpaper_bridge.dart';

void main() {
  testWidgets('WakeWall starts with an empty collection', (tester) async {
    final controller = WakeWallController(bridge: _EmptyBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('WakeWall'), findsOneWidget);
    expect(find.text('Add Images'), findsOneWidget);
    expect(find.text('Up Next'), findsNothing);
  });

  testWidgets('WakeWall renders the populated home screen', (tester) async {
    final controller = WakeWallController(bridge: _PopulatedBridge());
    await tester.pumpWidget(WakeWallApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('WakeWall'), findsOneWidget);
    expect(find.text('Up Next'), findsOneWidget);
    expect(find.text('ADD'), findsOneWidget);

    final firstThumbnail = tester.getSize(
      find.byKey(const ValueKey('wallpaper-thumbnail-0')),
    );
    final secondThumbnail = tester.getSize(
      find.byKey(const ValueKey('wallpaper-thumbnail-1')),
    );
    expect(firstThumbnail.height, greaterThan(firstThumbnail.width * 1.5));
    expect(firstThumbnail, secondThumbnail);
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
  @override
  Future<Map<String, Object?>> configuration() async => {
    'index': 0,
    'paused': false,
    'shuffle': false,
    'fit': 'cropToFill',
    'wallpapers': List.generate(
      4,
      (index) => {
        'sampleIndex': index,
        'crop': const {'scale': 1.0, 'offsetX': 0.0, 'offsetY': 0.0},
      },
    ),
  };
}
