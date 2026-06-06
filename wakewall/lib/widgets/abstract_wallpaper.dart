import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/wallpaper.dart';

class AbstractWallpaper extends StatelessWidget {
  const AbstractWallpaper({
    required this.wallpaper,
    this.borderRadius = BorderRadius.zero,
    this.crop,
    super.key,
  });

  final Wallpaper wallpaper;
  final BorderRadius borderRadius;
  final WallpaperCrop? crop;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final activeCrop = crop ?? wallpaper.crop;
          return Transform.translate(
            offset: Offset(
              constraints.maxWidth * activeCrop.offsetX,
              constraints.maxHeight * activeCrop.offsetY,
            ),
            child: Transform.scale(
              scale: activeCrop.scale,
              child: wallpaper.thumbnail != null
                  ? Image.memory(
                      wallpaper.thumbnail!,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  : wallpaper.isUserImage
                  ? const ColoredBox(
                      color: Color(0xFF202124),
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Color(0xFFA7A9B0),
                        ),
                      ),
                    )
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
