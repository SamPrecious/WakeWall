import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;

import '../controllers/wakewall_controller.dart';
import '../models/wallpaper.dart';
import '../theme/wakewall_theme.dart';
import '../widgets/abstract_wallpaper.dart';

void _cropTapHaptic() {
  HapticFeedback.selectionClick();
}

void _cropCommitHaptic() {
  HapticFeedback.mediumImpact();
}

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
  late WallpaperDisplayMode displayMode;
  late Color fitBackgroundColor;
  double gestureStartScale = 1;
  Offset gestureStartFocalPoint = Offset.zero;
  double gestureStartX = 0;
  double gestureStartY = 0;
  bool saving = false;
  bool aiFillReady = false;
  bool aiFillGenerating = false;

  Wallpaper get wallpaper =>
      widget.controller.wallpapers[widget.wallpaperIndex];

  bool get canReset =>
      !crop.isDefault ||
      displayMode != WallpaperDisplayMode.fill ||
      fitBackgroundColor != const Color(0xFF202124);

  @override
  void initState() {
    super.initState();
    crop = wallpaper.crop;
    displayMode = wallpaper.displayMode;
    fitBackgroundColor = wallpaper.fitBackgroundColor;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _EditorHeader(
              saving: saving,
              onCancel: () {
                _cropTapHaptic();
                context.router.pop();
              },
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
                        behavior: HitTestBehavior.opaque,
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
                          final baseScale =
                              displayMode == WallpaperDisplayMode.fill
                              ? math.max(
                                  width / sourceWidth,
                                  height / sourceHeight,
                                )
                              : math.min(
                                  width / sourceWidth,
                                  height / sourceHeight,
                                );
                          final maxOffsetX =
                              math.max(
                                0,
                                sourceWidth * baseScale * nextScale - width,
                              ) /
                              (2 * width);
                          final maxOffsetY =
                              math.max(
                                0,
                                sourceHeight * baseScale * nextScale - height,
                              ) /
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
                                  displayMode: displayMode,
                                  fitBackgroundColor: fitBackgroundColor,
                                  previewBytes: wallpaper.preview,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _CropGridPainter(
                                      context.wakeWallColors.teal,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 14,
                                right: 14,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 240),
                                  reverseDuration: const Duration(
                                    milliseconds: 180,
                                  ),
                                  switchInCurve: Curves.easeOut,
                                  switchOutCurve: Curves.easeIn,
                                  child: canReset
                                      ? _CropOverlayButton(
                                          key: const ValueKey(
                                            'crop-reset-visible',
                                          ),
                                          icon: Icons.restart_alt_rounded,
                                          tooltip: 'Reset wallpaper',
                                          onTap: _reset,
                                        )
                                      : const SizedBox(
                                          key: ValueKey('crop-reset-hidden'),
                                          width: 48,
                                          height: 48,
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
            _EditorFooter(
              crop: crop,
              displayMode: displayMode,
              fitBackgroundColor: fitBackgroundColor,
              onDisplayModeChanged: (value) {
                if (value != displayMode) _cropTapHaptic();
                setState(() => displayMode = value);
              },
              onFitBackgroundColorChanged: (value) {
                if (value != fitBackgroundColor) _cropTapHaptic();
                setState(() => fitBackgroundColor = value);
              },
              aiFillReady: aiFillReady,
              aiFillGenerating: aiFillGenerating,
              onAiFillSelected: _prepareAiFill,
              onAiFillGenerate: _generateAiFill,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    _cropCommitHaptic();
    setState(() => saving = true);
    await widget.controller.updateCrop(
      widget.wallpaperIndex,
      crop,
      displayMode: displayMode,
      fitBackgroundColor: fitBackgroundColor,
    );
    if (!mounted) return;
    context.router.pop();
  }

  void _reset() {
    _cropCommitHaptic();
    setState(() {
      crop = const WallpaperCrop();
      displayMode = WallpaperDisplayMode.fill;
      fitBackgroundColor = const Color(0xFF202124);
    });
  }

  Future<void> _prepareAiFill() async {
    _cropTapHaptic();
    if (!mounted) return;
    setState(() => aiFillReady = true);
  }

  Future<void> _generateAiFill() async {
    if (aiFillGenerating) return;
    final sourceBytes = wallpaper.preview;
    if (sourceBytes == null) {
      _showCropMessage('AI Fill could not load the source photo preview.');
      return;
    }

    _cropCommitHaptic();
    setState(() => aiFillGenerating = true);
    try {
      final input = await _buildAiFillInput(sourceBytes);
      final inpainted = await widget.controller.inpaintAiFill(
        imageBytes: input.imageBytes,
        maskBytes: input.maskBytes,
      );
      final generated = _restoreKnownAiFillPixels(input, inpainted);
      final imported = await widget.controller.addGeneratedWallpaper(
        generated,
        name: '${wallpaper.name} AI Fill.jpg',
      );
      if (!mounted) return;
      _showCropMessage(
        imported ? 'AI filled wallpaper added.' : 'AI fill returned no image.',
      );
      if (imported) context.router.pop();
    } catch (error) {
      if (!mounted) return;
      _showCropMessage('AI Fill failed: $error');
    } finally {
      if (mounted) setState(() => aiFillGenerating = false);
    }
  }

  Future<_AiFillInput> _buildAiFillInput(Uint8List sourceBytes) async {
    final source = image.decodeImage(sourceBytes);
    if (source == null) throw 'Could not read the wallpaper preview.';

    const outputWidth = 768;
    final phoneRatio = _phoneRatio(context);
    final outputHeight = (outputWidth / phoneRatio).round();
    final hidden = image.ColorRgb8(0, 0, 0);
    final known = image.ColorRgb8(255, 255, 255);
    final canvas = image.Image(width: outputWidth, height: outputHeight);
    final mask = image.Image(width: outputWidth, height: outputHeight);
    image.fill(canvas, color: hidden);
    image.fill(mask, color: hidden);

    final containScale = math.min(
      outputWidth / source.width,
      outputHeight / source.height,
    );
    final drawnWidth = (source.width * containScale * crop.scale).round();
    final drawnHeight = (source.height * containScale * crop.scale).round();
    final resized = image.copyResize(
      source,
      width: math.max(1, drawnWidth),
      height: math.max(1, drawnHeight),
      interpolation: image.Interpolation.cubic,
    );
    final offsetX =
        (outputWidth - drawnWidth) ~/ 2 + (crop.offsetX * outputWidth).round();
    final offsetY =
        (outputHeight - drawnHeight) ~/ 2 +
        (crop.offsetY * outputHeight).round();
    image.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);
    final left = math.max(0, offsetX);
    final top = math.max(0, offsetY);
    final right = math.min(outputWidth, offsetX + resized.width);
    final bottom = math.min(outputHeight, offsetY + resized.height);
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        mask.setPixel(x, y, known);
      }
    }

    return _AiFillInput(
      imageBytes: Uint8List.fromList(image.encodeJpg(canvas, quality: 92)),
      maskBytes: Uint8List.fromList(image.encodePng(mask)),
    );
  }

  Uint8List _restoreKnownAiFillPixels(
    _AiFillInput input,
    Uint8List inpaintedBytes,
  ) {
    final canvas = image.decodeImage(input.imageBytes);
    final mask = image.decodeImage(input.maskBytes);
    final inpainted = image.decodeImage(inpaintedBytes);
    if (canvas == null || mask == null || inpainted == null) {
      throw 'AI Fill returned an unreadable image.';
    }
    if (canvas.width != inpainted.width || canvas.height != inpainted.height) {
      throw 'AI Fill returned the wrong image size.';
    }
    for (var y = 0; y < inpainted.height; y++) {
      for (var x = 0; x < inpainted.width; x++) {
        if (mask.getPixel(x, y).r > 127) {
          inpainted.setPixel(x, y, canvas.getPixel(x, y));
        }
      }
    }
    return Uint8List.fromList(image.encodeJpg(inpainted, quality: 95));
  }

  void _showCropMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

double _phoneRatio(BuildContext context) {
  final physicalSize = View.of(context).physicalSize;
  final displayWidth = math.min(physicalSize.width, physicalSize.height);
  final displayHeight = math.max(physicalSize.width, physicalSize.height);
  if (displayWidth > 0 && displayHeight > 0) {
    return (displayWidth / displayHeight).clamp(.44, .62).toDouble();
  }
  final screen = MediaQuery.sizeOf(context);
  return (screen.width / screen.height).clamp(.44, .62).toDouble();
}

class _AiFillInput {
  const _AiFillInput({required this.imageBytes, required this.maskBytes});

  final Uint8List imageBytes;
  final Uint8List maskBytes;
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final compactButtonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 84),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Adjust Wallpaper',
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    letterSpacing: -.2,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('crop-editor-cancel'),
                style: compactButtonStyle,
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('crop-editor-save'),
                style: compactButtonStyle,
                onPressed: saving ? null : onSave,
                child: Text(saving ? 'Saving' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorFooter extends StatelessWidget {
  const _EditorFooter({
    required this.crop,
    required this.displayMode,
    required this.fitBackgroundColor,
    required this.onDisplayModeChanged,
    required this.onFitBackgroundColorChanged,
    required this.aiFillReady,
    required this.aiFillGenerating,
    required this.onAiFillSelected,
    required this.onAiFillGenerate,
  });

  final WallpaperCrop crop;
  final WallpaperDisplayMode displayMode;
  final Color fitBackgroundColor;
  final ValueChanged<WallpaperDisplayMode> onDisplayModeChanged;
  final ValueChanged<Color> onFitBackgroundColorChanged;
  final bool aiFillReady;
  final bool aiFillGenerating;
  final VoidCallback onAiFillSelected;
  final VoidCallback onAiFillGenerate;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<WallpaperDisplayMode>(
              segments: const [
                ButtonSegment(
                  value: WallpaperDisplayMode.fill,
                  label: Text('Fill'),
                  icon: Icon(Icons.crop_free_rounded),
                ),
                ButtonSegment(
                  value: WallpaperDisplayMode.blur,
                  label: Text('Blur'),
                  icon: Icon(Icons.blur_on_rounded),
                ),
                ButtonSegment(
                  value: WallpaperDisplayMode.fit,
                  label: Text('Fit'),
                  icon: Icon(Icons.fit_screen_rounded),
                ),
              ],
              selected: {displayMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  onDisplayModeChanged(selection.first),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: aiFillGenerating ? null : onAiFillSelected,
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('AI Fill'),
                ),
              ),
              if (aiFillReady) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: aiFillGenerating ? null : onAiFillGenerate,
                    icon: aiFillGenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      aiFillGenerating ? 'Generating' : 'Generate Borders',
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: displayMode == WallpaperDisplayMode.fit
                ? _FitBackgroundSelector(
                    selected: fitBackgroundColor,
                    onSelected: onFitBackgroundColorChanged,
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pinch_rounded, size: 18, color: colors.muted),
                      const SizedBox(width: 8),
                      Text(
                        crop.isDefault
                            ? 'Pinch to zoom | Drag to position'
                            : '${crop.scale.toStringAsFixed(1)}x zoom | Drag to position',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: colors.muted),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CropOverlayButton extends StatelessWidget {
  const _CropOverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xCC25262A),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          key: const ValueKey('crop-editor-reset'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: const Color(0xFFE3E3E8), size: 21),
          ),
        ),
      ),
    );
  }
}

class _FitBackgroundSelector extends StatelessWidget {
  const _FitBackgroundSelector({
    required this.selected,
    required this.onSelected,
  });

  static const colors = [
    Color(0xFF202124),
    Color(0xFF000000),
    Color(0xFFE8EAED),
    Color(0xFF182230),
    Color(0xFF183029),
    Color(0xFF3A2026),
    Color(0xFF3A2C22),
  ];

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final themeColors = context.wakeWallColors;
    return Semantics(
      label: 'Fit background colour',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Border',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: themeColors.muted),
            ),
            const SizedBox(width: 12),
            for (final color in colors)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onSelected(color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color == selected
                            ? themeColors.tealStrong
                            : themeColors.outline,
                        width: color == selected ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CropGridPainter extends CustomPainter {
  const _CropGridPainter(this.accent);

  final Color accent;

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
        ..color = accent.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropGridPainter oldDelegate) =>
      oldDelegate.accent != accent;
}
