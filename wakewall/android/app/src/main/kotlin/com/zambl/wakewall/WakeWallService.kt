package com.zambl.wakewall

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import kotlin.math.max
import kotlin.math.min

class WakeWallService : WallpaperService() {
    override fun onCreateEngine(): Engine = WakeWallEngine()

    inner class WakeWallEngine : Engine() {
        private val handler = Handler(Looper.getMainLooper())
        private val store = WakeWallStore(this@WakeWallService)
        private var visible = false
        private var screenOffHandled = false
        private var currentIndex = store.index
        private var preparedIndex = currentIndex
        private var preparedBitmap: Bitmap? = null

        private val rebuildRunner = Runnable { redrawCurrentAndPrepare() }

        private val screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> handleScreenOff()
                    Intent.ACTION_SCREEN_ON -> {
                        screenOffHandled = false
                        store.recordEvent("screen_on")
                    }
                    ACTION_CONFIGURATION_UPDATED -> {
                        currentIndex = store.index
                        invalidatePreparedFrame()
                        handler.post(rebuildRunner)
                    }
                    ACTION_CROP_UPDATED -> {
                        invalidatePreparedFrame()
                        handler.post(rebuildRunner)
                    }
                }
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(ACTION_CONFIGURATION_UPDATED)
                addAction(ACTION_CROP_UPDATED)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(screenReceiver, filter, RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(screenReceiver, filter)
            }
        }

        override fun onDestroy() {
            handler.removeCallbacks(rebuildRunner)
            invalidatePreparedFrame()
            runCatching { unregisterReceiver(screenReceiver) }
            super.onDestroy()
        }

        override fun onVisibilityChanged(isVisible: Boolean) {
            visible = isVisible
            if (isVisible) handler.post(rebuildRunner)
        }

        override fun onSurfaceChanged(
            holder: SurfaceHolder,
            format: Int,
            width: Int,
            height: Int,
        ) {
            super.onSurfaceChanged(holder, format, width, height)
            handler.post(rebuildRunner)
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            visible = false
            handler.removeCallbacks(rebuildRunner)
            super.onSurfaceDestroyed(holder)
        }

        // Switches to the prepared wallpaper as the screen begins turning off.
        private fun handleScreenOff() {
            if (screenOffHandled) return
            screenOffHandled = true
            handler.removeCallbacks(rebuildRunner)

            val nextIndex = if (preparedIndex != currentIndex) {
                preparedIndex
            } else {
                store.nextIndex(currentIndex)
            }
            val prepared = preparedBitmap?.takeIf { preparedIndex == nextIndex && !it.isRecycled }
            val drawSucceeded = postFrame(
                index = nextIndex,
                bitmap = prepared,
                allowHidden = true,
            )

            currentIndex = nextIndex
            store.commitScreenOff(
                next = nextIndex,
                drawSucceeded = drawSucceeded,
                usedPreparedFrame = prepared != null,
            )

            // Prepares the following wallpaper immediately for another quick cycle.
            prepareNextFrame()
        }

        // Refreshes the visible wallpaper and keeps the next one ready.
        private fun redrawCurrentAndPrepare() {
            currentIndex = store.index
            postFrame(
                index = currentIndex,
                bitmap = null,
                allowHidden = false,
            )
            prepareNextFrame()
        }

        // Reuses one bitmap buffer so preparing wallpapers creates less work.
        private fun prepareNextFrame() {
            val frame = surfaceHolder.surfaceFrame
            if (frame.width() <= 0 || frame.height() <= 0) return

            val nextIndex = store.nextIndex(currentIndex)
            val existing = preparedBitmap
            if (preparedIndex == nextIndex &&
                existing != null &&
                !existing.isRecycled &&
                existing.width == frame.width() &&
                existing.height == frame.height()
            ) {
                return
            }

            val bitmap = existing
                ?.takeIf {
                    !it.isRecycled &&
                        it.width == frame.width() &&
                        it.height == frame.height()
                }
                ?: runCatching {
                    Bitmap.createBitmap(frame.width(), frame.height(), Bitmap.Config.ARGB_8888)
                }.getOrNull()
                ?: return
            drawWallpaper(Canvas(bitmap), nextIndex)
            if (bitmap !== existing) invalidatePreparedFrame()
            preparedBitmap = bitmap
            preparedIndex = nextIndex
        }

        private fun invalidatePreparedFrame() {
            preparedBitmap?.takeUnless { it.isRecycled }?.recycle()
            preparedBitmap = null
            preparedIndex = currentIndex
        }

        // Draws a frame to Android's wallpaper surface, including while hidden.
        private fun postFrame(
            index: Int,
            bitmap: Bitmap?,
            allowHidden: Boolean,
        ): Boolean {
            if (!visible && !allowHidden) return false
            var canvas: Canvas? = null
            var drewFrame = false
            try {
                canvas = surfaceHolder.lockCanvas()
                if (canvas != null) {
                    if (bitmap != null) {
                        canvas.drawBitmap(bitmap, 0f, 0f, null)
                    } else {
                        drawWallpaper(canvas, index)
                    }
                    drewFrame = true
                }
            } catch (_: Exception) {
                drewFrame = false
            } finally {
                val posted = canvas != null && runCatching {
                    surfaceHolder.unlockCanvasAndPost(canvas)
                }.isSuccess
                return drewFrame && posted
            }
        }

        // Draws either a selected photo or one of the bundled samples.
        private fun drawWallpaper(canvas: Canvas, index: Int) {
            val entry = store.wallpaperAt(index)
            if (entry == null) {
                canvas.drawColor(Color.BLACK)
                return
            }
            if (!entry.startsWith("sample:")) {
                if (!drawPhoto(canvas, index, entry)) canvas.drawColor(Color.BLACK)
                return
            }
            drawSample(canvas, entry.removePrefix("sample:").toIntOrNull() ?: index, index)
        }

        private fun drawPhoto(canvas: Canvas, index: Int, uriValue: String): Boolean {
            val width = canvas.width.toFloat()
            val height = canvas.height.toFloat()
            val bitmap = decodePhoto(uriValue, canvas.width, canvas.height) ?: return false
            val crop = store.crop(index)
            canvas.drawColor(Color.BLACK)
            canvas.save()

            val scale = if (store.fit == "fitEntireImage") {
                min(width / bitmap.width, height / bitmap.height)
            } else {
                max(width / bitmap.width, height / bitmap.height)
            }
            val drawnWidth = bitmap.width * scale
            val drawnHeight = bitmap.height * scale
            val maxOffsetX = max(0f, (drawnWidth * crop.scale - width) / (2f * width))
            val maxOffsetY = max(0f, (drawnHeight * crop.scale - height) / (2f * height))
            applyCrop(
                canvas,
                crop.copy(
                    offsetX = crop.offsetX.coerceIn(-maxOffsetX, maxOffsetX),
                    offsetY = crop.offsetY.coerceIn(-maxOffsetY, maxOffsetY),
                ),
                width,
                height,
            )
            val destination = RectF(
                (width - drawnWidth) / 2f,
                (height - drawnHeight) / 2f,
                (width + drawnWidth) / 2f,
                (height + drawnHeight) / 2f,
            )
            canvas.drawBitmap(bitmap, null, destination, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
            canvas.restore()
            bitmap.recycle()
            return true
        }

        // Loads a camera photo near the screen size and respects its saved orientation.
        private fun decodePhoto(uriValue: String, targetWidth: Int, targetHeight: Int): Bitmap? {
            return runCatching {
                val localFile = store.localFile(uriValue)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val source = if (localFile != null) {
                        ImageDecoder.createSource(localFile)
                    } else {
                        ImageDecoder.createSource(contentResolver, android.net.Uri.parse(uriValue))
                    }
                    ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                        val widthScale = targetWidth / info.size.width.toFloat()
                        val heightScale = targetHeight / info.size.height.toFloat()
                        val scale = (
                            if (store.fit == "fitEntireImage") {
                                min(widthScale, heightScale)
                            } else {
                                max(widthScale, heightScale)
                            }
                        ).coerceAtMost(1f)
                        decoder.setTargetSize(
                            max(1, (info.size.width * scale).toInt()),
                            max(1, (info.size.height * scale).toInt()),
                        )
                        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    }
                } else {
                    store.openImage(uriValue)?.use(BitmapFactory::decodeStream)
                }
            }.getOrNull()
        }

        // Builds one of the bundled sample wallpapers directly onto the surface.
        private fun drawSample(canvas: Canvas, sampleIndex: Int, cropIndex: Int) {
            val width = canvas.width.toFloat()
            val height = canvas.height.toFloat()
            val crop = store.crop(cropIndex)
            canvas.save()
            applyCrop(canvas, crop, width, height)
            val palettes = arrayOf(
                intArrayOf(Color.rgb(6, 18, 16), Color.rgb(18, 62, 61), Color.rgb(138, 228, 220)),
                intArrayOf(Color.rgb(8, 11, 11), Color.rgb(60, 69, 67), Color.rgb(205, 213, 210)),
                intArrayOf(Color.rgb(4, 13, 11), Color.rgb(16, 38, 34), Color.rgb(52, 117, 110)),
                intArrayOf(Color.rgb(11, 16, 16), Color.rgb(40, 49, 47), Color.rgb(113, 128, 124)),
            )
            val palette = palettes[sampleIndex.mod(palettes.size)]
            val background = Paint().apply {
                shader = LinearGradient(0f, 0f, width, height, palette[0], palette[1], Shader.TileMode.CLAMP)
            }
            canvas.drawRect(0f, 0f, width, height, background)

            val glow = Paint().apply {
                shader = RadialGradient(
                    width * .76f,
                    height * .23f,
                    max(width, height) * .64f,
                    intArrayOf(withAlpha(palette[2], 85), Color.TRANSPARENT),
                    floatArrayOf(0f, 1f),
                    Shader.TileMode.CLAMP,
                )
            }
            canvas.drawRect(0f, 0f, width, height, glow)

            repeat(14) { line ->
                val t = line / 13f
                val path = Path()
                if (sampleIndex % 2 == 0) {
                    path.moveTo(-width * .3f, height * (.72f + t * .18f))
                    path.cubicTo(
                        width * (.1f + t * .2f),
                        height * (.74f - t * .5f),
                        width * (.56f + t * .2f),
                        height * (.78f - t * .7f),
                        width * 1.25f,
                        height * (.12f + t * .28f),
                    )
                } else {
                    path.moveTo(width * (.15f + t * .06f), -height * .08f)
                    path.cubicTo(
                        width * (.14f + t * .6f),
                        height * .28f,
                        width * (.02f + t * .2f),
                        height * .64f,
                        width * (.68f + t * .42f),
                        height * 1.08f,
                    )
                }
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeCap = Paint.Cap.ROUND
                    strokeWidth = width * (.012f + t * .018f)
                    color = blend(palette[1], palette[2], t, (60 + t * 115).toInt())
                }
                canvas.drawPath(path, paint)
            }
            canvas.restore()
        }

        private fun applyCrop(canvas: Canvas, crop: CropTransform, width: Float, height: Float) {
            canvas.translate(width / 2f + crop.offsetX * width, height / 2f + crop.offsetY * height)
            canvas.scale(crop.scale, crop.scale)
            canvas.translate(-width / 2f, -height / 2f)
        }

        private fun withAlpha(color: Int, alpha: Int): Int =
            Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))

        private fun blend(first: Int, second: Int, t: Float, alpha: Int): Int = Color.argb(
            alpha,
            (Color.red(first) + (Color.red(second) - Color.red(first)) * t).toInt(),
            (Color.green(first) + (Color.green(second) - Color.green(first)) * t).toInt(),
            (Color.blue(first) + (Color.blue(second) - Color.blue(first)) * t).toInt(),
        )
    }

    companion object {
        const val ACTION_CONFIGURATION_UPDATED = "com.zambl.wakewall.CONFIGURATION_UPDATED"
        const val ACTION_CROP_UPDATED = "com.zambl.wakewall.CROP_UPDATED"
    }
}
