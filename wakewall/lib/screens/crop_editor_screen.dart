import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../controllers/wakewall_controller.dart';
import '../models/wallpaper.dart';
import '../theme/wakewall_theme.dart';
import '../widgets/abstract_wallpaper.dart';

@RoutePage()
class CropEditorScreen extends StatefulWidget {
  const CropEditorScreen({
    required this.controller,
    required this.wallpaperIndex,
    super.key,
  });

  final WakeWallController controller;
  final int wallpaperIndex;

  @override
  State<CropEditorScreen> createState() => _CropEditorScreenState();
}

class _CropEditorScreenState extends State<CropEditorScreen> {
  late WallpaperCrop crop;
  double gestureStartScale = 1;
  Offset gestureStartFocalPoint = Offset.zero;
  double gestureStartX = 0;
  double gestureStartY = 0;
  bool saving = false;

  Wallpaper get wallpaper =>
      widget.controller.wallpapers[widget.wallpaperIndex];

  @override
  void initState() {
    super.initState();
    crop = wallpaper.crop;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _EditorHeader(
              wallpaperName: wallpaper.name,
              saving: saving,
              canReset: !crop.isDefault,
              onCancel: () => context.router.pop(),
              onReset: () => setState(() => crop = const WallpaperCrop()),
              onSave: _save,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screen = MediaQuery.sizeOf(context);
                  final phoneRatio = (screen.width / screen.height).clamp(
                    .44,
                    .62,
                  );
                  final height = math.min(
                    constraints.maxHeight - 34,
                    (constraints.maxWidth - 40) / phoneRatio,
                  );
                  final width = height * phoneRatio;

                  return Center(
                    child: Semantics(
                      label: 'Wallpaper crop preview',
                      hint: 'Drag to position and pinch to zoom',
                      image: true,
                      child: GestureDetector(
                        onScaleStart: (details) {
                          gestureStartScale = crop.scale;
                          gestureStartFocalPoint = details.focalPoint;
                          gestureStartX = crop.offsetX;
                          gestureStartY = crop.offsetY;
                        },
                        onScaleUpdate: (details) {
                          final nextScale = (gestureStartScale * details.scale)
                              .clamp(1.0, 4.0);
                          final delta =
                              details.focalPoint - gestureStartFocalPoint;
                          final sourceWidth =
                              wallpaper.imageWidth?.toDouble() ?? width;
                          final sourceHeight =
                              wallpaper.imageHeight?.toDouble() ?? height;
                          final coverScale = math.max(
                            width / sourceWidth,
                            height / sourceHeight,
                          );
                          final maxOffsetX =
                              (sourceWidth * coverScale * nextScale - width) /
                              (2 * width);
                          final maxOffsetY =
                              (sourceHeight * coverScale * nextScale - height) /
                              (2 * height);
                          // Keeps the wallpaper inside the preview while it is moved.
                          setState(() {
                            crop = WallpaperCrop(
                              scale: nextScale,
                              offsetX: (gestureStartX + delta.dx / width).clamp(
                                -maxOffsetX,
                                maxOffsetX,
                              ),
                              offsetY: (gestureStartY + delta.dy / height)
                                  .clamp(-maxOffsetY, maxOffsetY),
                            );
                          });
                        },
                        child: ExcludeSemantics(
                          child: Stack(
                            children: [
                              SizedBox(
                                width: width,
                                height: height,
                                child: AbstractWallpaper(
                                  wallpaper: wallpaper,
                                  crop: crop,
                                  previewBytes: wallpaper.preview,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: const _CropGridPainter(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            _EditorFooter(crop: crop),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => saving = true);
    await widget.controller.updateCrop(widget.wallpaperIndex, crop);
    if (!mounted) return;
    context.router.pop();
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.wallpaperName,
    required this.saving,
    required this.canReset,
    required this.onCancel,
    required this.onReset,
    required this.onSave,
  });

  final String wallpaperName;
  final bool saving;
  final bool canReset;
  final VoidCallback onCancel;
  final VoidCallback onReset;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Row(
        children: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Adjust crop',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  wallpaperName,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: WakeWallColors.muted),
                ),
              ],
            ),
          ),
          if (canReset)
            IconButton(
              onPressed: onReset,
              tooltip: 'Reset crop',
              icon: const Icon(
                Icons.restart_alt_rounded,
                color: WakeWallColors.muted,
              ),
            ),
          TextButton(
            onPressed: saving ? null : onSave,
            child: Text(saving ? 'Saving' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _EditorFooter extends StatelessWidget {
  const _EditorFooter({required this.crop});

  final WallpaperCrop crop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.pinch_rounded,
            size: 18,
            color: WakeWallColors.muted,
          ),
          const SizedBox(width: 8),
          Text(
            crop.isDefault
                ? 'Pinch to zoom | Drag to position'
                : '${crop.scale.toStringAsFixed(1)}x zoom | Drag to position',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: WakeWallColors.muted),
          ),
        ],
      ),
    );
  }
}

class _CropGridPainter extends CustomPainter {
  const _CropGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Draws a simple rule-of-thirds guide over the crop preview.
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .18)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
      Paint()
        ..color = WakeWallColors.teal.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
