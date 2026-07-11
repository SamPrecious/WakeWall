import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/wallpaper.dart';

// Draws the same wallpaper model for the home preview, crop editor, and tiles.
class AbstractWallpaper extends StatelessWidget {
  const AbstractWallpaper({
    required this.wallpaper,
    this.borderRadius = BorderRadius.zero,
    this.crop,
    this.displayMode,
    this.fitBackgroundColor,
    this.previewBytes,
    this.applyCrop = true,
    this.filterQuality = FilterQuality.high,
    this.rotationQuarterTurns = 0,
    super.key,
  });

  final Wallpaper wallpaper;
  final BorderRadius borderRadius;
  final WallpaperCrop? crop;
  final WallpaperDisplayMode? displayMode;
  final Color? fitBackgroundColor;
  final Uint8List? previewBytes;
  final bool applyCrop;
  final FilterQuality filterQuality;
  final int rotationQuarterTurns;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final activeCrop = crop ?? wallpaper.crop;
          final activeMode = displayMode ?? wallpaper.displayMode;
          final activeFitColor =
              fitBackgroundColor ?? wallpaper.fitBackgroundColor;
          final imageBytes = previewBytes ?? wallpaper.thumbnail;
          final turns = ((rotationQuarterTurns % 4) + 4) % 4;
          final rotatedSideways = turns.isOdd;
          // Rotation swaps the rendered dimensions before crop math is applied.
          Widget memoryImage({
            required BoxFit fit,
            double? width,
            double? height,
            FilterQuality? quality,
          }) {
            final image = Image.memory(
              imageBytes!,
              width: rotatedSideways ? height : width,
              height: rotatedSideways ? width : height,
              fit: fit,
              gaplessPlayback: true,
              filterQuality: quality ?? filterQuality,
              errorBuilder: (_, _, _) => const _BrokenWallpaperPlaceholder(),
            );
            return turns == 0
                ? image
                : RotatedBox(quarterTurns: turns, child: image);
          }

          if (imageBytes != null && !applyCrop) {
            return memoryImage(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              fit: BoxFit.cover,
            );
          }
          final useFullSource =
              imageBytes != null &&
              wallpaper.imageWidth != null &&
              wallpaper.imageHeight != null;
          if (imageBytes != null && activeMode != WallpaperDisplayMode.fill) {
            // Fit and Blur contain the whole image, then apply crop offsets inside that frame.
            final sourceWidth =
                (rotatedSideways ? wallpaper.imageHeight : wallpaper.imageWidth)
                    ?.toDouble() ??
                constraints.maxWidth;
            final sourceHeight =
                (rotatedSideways ? wallpaper.imageWidth : wallpaper.imageHeight)
                    ?.toDouble() ??
                constraints.maxHeight;
            final containScale = math.min(
              constraints.maxWidth / sourceWidth,
              constraints.maxHeight / sourceHeight,
            );
            final drawnWidth = sourceWidth * containScale;
            final drawnHeight = sourceHeight * containScale;
            final maxOffsetX = math.max(
              0.0,
              (drawnWidth * activeCrop.scale - constraints.maxWidth) /
                  (2 * constraints.maxWidth),
            );
            final maxOffsetY = math.max(
              0.0,
              (drawnHeight * activeCrop.scale - constraints.maxHeight) /
                  (2 * constraints.maxHeight),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                if (activeMode == WallpaperDisplayMode.blur)
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Transform.scale(
                      scale: 1.12,
                      child: memoryImage(
                        fit: BoxFit.cover,
                        quality: FilterQuality.medium,
                      ),
                    ),
                  )
                else
                  ColoredBox(color: activeFitColor),
                OverflowBox(
                  alignment: Alignment.center,
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: Transform.translate(
                    offset: Offset(
                      constraints.maxWidth *
                          activeCrop.offsetX.clamp(-maxOffsetX, maxOffsetX),
                      constraints.maxHeight *
                          activeCrop.offsetY.clamp(-maxOffsetY, maxOffsetY),
                    ),
                    child: Transform.scale(
                      scale: activeCrop.scale,
                      child: SizedBox(
                        width: drawnWidth,
                        height: drawnHeight,
                        child: memoryImage(fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          if (imageBytes != null && useFullSource) {
            // Fill mode computes cover geometry from the source aspect ratio, not the widget size.
            final sourceWidth =
                (rotatedSideways
                        ? wallpaper.imageHeight!
                        : wallpaper.imageWidth!)
                    .toDouble();
            final sourceHeight =
                (rotatedSideways
                        ? wallpaper.imageWidth!
                        : wallpaper.imageHeight!)
                    .toDouble();
            final coverScale = math.max(
              constraints.maxWidth / sourceWidth,
              constraints.maxHeight / sourceHeight,
            );
            final drawnWidth = sourceWidth * coverScale;
            final drawnHeight = sourceHeight * coverScale;
            final maxOffsetX = math.max(
              0.0,
              (drawnWidth * activeCrop.scale - constraints.maxWidth) /
                  (2 * constraints.maxWidth),
            );
            final maxOffsetY = math.max(
              0.0,
              (drawnHeight * activeCrop.scale - constraints.maxHeight) /
                  (2 * constraints.maxHeight),
            );
            final offsetX = activeCrop.offsetX.clamp(-maxOffsetX, maxOffsetX);
            final offsetY = activeCrop.offsetY.clamp(-maxOffsetY, maxOffsetY);
            return OverflowBox(
              alignment: Alignment.center,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Transform.translate(
                offset: Offset(
                  constraints.maxWidth * offsetX,
                  constraints.maxHeight * offsetY,
                ),
                child: Transform.scale(
                  scale: activeCrop.scale,
                  child: SizedBox(
                    width: drawnWidth,
                    height: drawnHeight,
                    child: memoryImage(fit: BoxFit.cover),
                  ),
                ),
              ),
            );
          }
          return Transform.translate(
            offset: Offset(
              constraints.maxWidth * activeCrop.offsetX,
              constraints.maxHeight * activeCrop.offsetY,
            ),
            child: Transform.scale(
              scale: activeCrop.scale,
              child: imageBytes != null
                  ? memoryImage(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      fit: BoxFit.cover,
                    )
                  : wallpaper.isUserImage
                  ? const _BrokenWallpaperPlaceholder()
                  : CustomPaint(
                      painter: _AbstractWallpaperPainter(wallpaper),
                      child: const SizedBox.expand(),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _BrokenWallpaperPlaceholder extends StatelessWidget {
  const _BrokenWallpaperPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF202124),
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: Color(0xFFA7A9B0)),
      ),
    );
  }
}

class _AbstractWallpaperPainter extends CustomPainter {
  const _AbstractWallpaperPainter(this.wallpaper);

  final Wallpaper wallpaper;

  @override
  void paint(Canvas canvas, Size size) {
    // Builds the bundled sample wallpaper from gradients and flowing lines.
    final rect = Offset.zero & size;
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [wallpaper.palette[0], wallpaper.palette[1]],
      ).createShader(rect);
    canvas.drawRect(rect, background);

    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              wallpaper.palette[2].withValues(alpha: .32),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * .75, size.height * .24),
              radius: size.longestSide * .62,
            ),
          );
    canvas.drawRect(rect, glow);

    final curvePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final count = 14;

    for (var i = 0; i < count; i++) {
      final t = i / (count - 1);
      final path = Path();
      final offset = (t - .5) * size.width * 1.7;
      if (wallpaper.style.isEven) {
        path.moveTo(-size.width * .3, size.height * (.72 + t * .18));
        path.cubicTo(
          size.width * (.1 + t * .2),
          size.height * (.74 - t * .5),
          size.width * (.56 + t * .2),
          size.height * (.78 - t * .7),
          size.width * 1.25,
          size.height * (.12 + t * .28),
        );
      } else {
        path.moveTo(size.width * (.15 + t * .06), -size.height * .08);
        path.cubicTo(
          size.width * (.14 + t * .6),
          size.height * .28,
          size.width * (.02 + t * .2),
          size.height * .64,
          size.width * (.68 + t * .42),
          size.height * 1.08,
        );
      }
      curvePaint
        ..color = Color.lerp(
          wallpaper.palette[1],
          wallpaper.palette[2],
          math.pow(t, 1.6).toDouble(),
        )!.withValues(alpha: .24 + t * .4)
        ..strokeWidth = size.shortestSide * (.012 + t * .018);
      canvas.save();
      canvas.translate(offset * .12, 0);
      canvas.drawPath(path, curvePaint);
      canvas.restore();
    }

    final shade = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Color(0xB3000000)],
        stops: [.35, 1],
      ).createShader(rect);
    canvas.drawRect(rect, shade);
  }

  @override
  bool shouldRepaint(_AbstractWallpaperPainter oldDelegate) =>
      oldDelegate.wallpaper != wallpaper;
}
