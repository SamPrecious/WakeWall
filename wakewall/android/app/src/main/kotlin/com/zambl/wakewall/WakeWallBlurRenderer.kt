package com.zambl.wakewall

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import kotlin.math.max
import kotlin.math.roundToInt

// Draws a smooth blurred cover image without leaving expensive blur work for screen-off.
object WakeWallBlurRenderer {
    fun draw(canvas: Canvas, source: Bitmap, width: Float, height: Float) {
        val blurWidth = max(1, (width / DOWNSAMPLE).roundToInt())
        val blurHeight = max(1, (height / DOWNSAMPLE).roundToInt())
        val backdrop = Bitmap.createBitmap(blurWidth, blurHeight, Bitmap.Config.ARGB_8888)
        val backdropCanvas = Canvas(backdrop)
        backdropCanvas.drawBitmap(
            source,
            coverRect(source.width, source.height, blurWidth.toFloat(), blurHeight.toFloat()),
            RectF(0f, 0f, blurWidth.toFloat(), blurHeight.toFloat()),
            Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG),
        )

        repeat(BLUR_PASSES) { boxBlur(backdrop, BLUR_RADIUS) }
        canvas.drawBitmap(
            backdrop,
            null,
            RectF(0f, 0f, width, height),
            Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG),
        )
        backdrop.recycle()
    }

    private fun coverRect(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Float,
        targetHeight: Float,
    ): Rect {
        val sourceRatio = sourceWidth.toFloat() / sourceHeight
        val targetRatio = targetWidth / targetHeight
        return if (sourceRatio > targetRatio) {
            val croppedWidth = (sourceHeight * targetRatio).roundToInt().coerceAtLeast(1)
            Rect((sourceWidth - croppedWidth) / 2, 0, (sourceWidth + croppedWidth) / 2, sourceHeight)
        } else {
            val croppedHeight = (sourceWidth / targetRatio).roundToInt().coerceAtLeast(1)
            Rect(0, (sourceHeight - croppedHeight) / 2, sourceWidth, (sourceHeight + croppedHeight) / 2)
        }
    }

    private fun boxBlur(bitmap: Bitmap, radius: Int) {
        // Two one-dimensional passes are much cheaper than sampling a full square per pixel.
        val width = bitmap.width
        val height = bitmap.height
        val source = IntArray(width * height)
        val target = IntArray(source.size)
        bitmap.getPixels(source, 0, width, 0, 0, width, height)
        blurHorizontal(source, target, width, height, radius)
        blurVertical(target, source, width, height, radius)
        bitmap.setPixels(source, 0, width, 0, 0, width, height)
    }

    private fun blurHorizontal(
        source: IntArray,
        target: IntArray,
        width: Int,
        height: Int,
        radius: Int,
    ) {
        val window = radius * 2 + 1
        for (y in 0 until height) {
            val row = y * width
            var red = 0
            var green = 0
            var blue = 0
            for (offset in -radius..radius) {
                val color = source[row + offset.coerceIn(0, width - 1)]
                red += color shr 16 and 0xff
                green += color shr 8 and 0xff
                blue += color and 0xff
            }
            for (x in 0 until width) {
                target[row + x] =
                    0xff000000.toInt() or
                        (red / window shl 16) or
                        (green / window shl 8) or
                        (blue / window)
                val leaving = source[row + (x - radius).coerceIn(0, width - 1)]
                val entering = source[row + (x + radius + 1).coerceIn(0, width - 1)]
                red += (entering shr 16 and 0xff) - (leaving shr 16 and 0xff)
                green += (entering shr 8 and 0xff) - (leaving shr 8 and 0xff)
                blue += (entering and 0xff) - (leaving and 0xff)
            }
        }
    }

    private fun blurVertical(
        source: IntArray,
        target: IntArray,
        width: Int,
        height: Int,
        radius: Int,
    ) {
        val window = radius * 2 + 1
        for (x in 0 until width) {
            var red = 0
            var green = 0
            var blue = 0
            for (offset in -radius..radius) {
                val color = source[offset.coerceIn(0, height - 1) * width + x]
                red += color shr 16 and 0xff
                green += color shr 8 and 0xff
                blue += color and 0xff
            }
            for (y in 0 until height) {
                target[y * width + x] =
                    0xff000000.toInt() or
                        (red / window shl 16) or
                        (green / window shl 8) or
                        (blue / window)
                val leaving = source[(y - radius).coerceIn(0, height - 1) * width + x]
                val entering = source[(y + radius + 1).coerceIn(0, height - 1) * width + x]
                red += (entering shr 16 and 0xff) - (leaving shr 16 and 0xff)
                green += (entering shr 8 and 0xff) - (leaving shr 8 and 0xff)
                blue += (entering and 0xff) - (leaving and 0xff)
            }
        }
    }

    private const val DOWNSAMPLE = 5f
    private const val BLUR_RADIUS = 9
    private const val BLUR_PASSES = 3
}
