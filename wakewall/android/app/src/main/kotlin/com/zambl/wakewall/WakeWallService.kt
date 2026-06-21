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
import android.graphics.Rect
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.service.wallpaper.WallpaperService
import android.view.Display
import android.view.SurfaceHolder
import android.hardware.display.DisplayManager
import androidx.core.content.ContextCompat
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class WakeWallService : WallpaperService() {
    override fun onCreateEngine(): Engine = WakeWallEngine()

    inner class WakeWallEngine : Engine() {
        private val handler = Handler(Looper.getMainLooper())
        private val bootFrameStore = WakeWallBootFrameStore(this@WakeWallService)
        private val store by lazy { WakeWallStore(this@WakeWallService) }
        private val powerManager = getSystemService(PowerManager::class.java)
        private val displayManager = getSystemService(DisplayManager::class.java)
        private val preparationExecutor = Executors.newSingleThreadExecutor()
        private var visible = false
        private var destroyed = false
        private var screenOffHandled = false
        private var currentIndex = 0
        private var currentFrameIndex = -1
        private var currentFrameBitmap: Bitmap? = null
        private var preparedIndex = -1
        private var preparedBitmap: Bitmap? = null
        private var preparationGeneration = 0
        private var preparingIndex = -1
        private var rebuildScheduled = false
        private var wallpaperXOffset = .5f
        private var scrollingEnabled = false

        private val rebuildRunner = Runnable {
            rebuildScheduled = false
            redrawCurrentAndPrepare()
        }

        private fun unlockedStore(): WakeWallStore? =
            if (bootFrameStore.credentialStorageAvailable()) store else null

        private val screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> handleScreenOff()
                    Intent.ACTION_SCREEN_ON -> {
                        restoreCurrentFrame()
                        screenOffHandled = false
                        unlockedStore()?.recordEvent("screen_on")
                        if (visible) scheduleRebuild()
                    }
                    Intent.ACTION_USER_UNLOCKED -> {
                        val activeStore = unlockedStore() ?: return
                        currentIndex = activeStore.index
                        updateScrollingMode(activeStore)
                        invalidateFrames()
                        scheduleRebuild()
                    }
                    ACTION_CONFIGURATION_UPDATED -> {
                        val activeStore = unlockedStore() ?: return
                        activeStore.refreshActiveWallpapers()
                        currentIndex = activeStore.index
                        updateScrollingMode(activeStore)
                        invalidateFrames()
                        scheduleRebuild()
                    }
                    ACTION_CROP_UPDATED -> {
                        invalidateFrames()
                        scheduleRebuild()
                    }
                }
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            unlockedStore()?.let { activeStore ->
                currentIndex = activeStore.index
                scrollingEnabled = activeStore.wallpaperScrolling
            }
            setOffsetNotificationsEnabled(scrollingEnabled)
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_UNLOCKED)
                addAction(ACTION_CONFIGURATION_UPDATED)
                addAction(ACTION_CROP_UPDATED)
            }
            ContextCompat.registerReceiver(
                this@WakeWallService,
                screenReceiver,
                filter,
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        }

        override fun onDestroy() {
            destroyed = true
            preparationGeneration += 1
            preparationExecutor.shutdownNow()
            handler.removeCallbacks(rebuildRunner)
            rebuildScheduled = false
            invalidateFrames()
            runCatching { unregisterReceiver(screenReceiver) }
            super.onDestroy()
        }

        override fun onVisibilityChanged(isVisible: Boolean) {
            visible = isVisible
            if (unlockedStore() == null) {
                postBootFrame(allowHidden = true)
                return
            }
            if (!isVisible && deviceIsTurningOff()) {
                handleScreenOff()
            } else if (isVisible || preparedBitmap == null) {
                scheduleRebuild()
            }
        }

        override fun onOffsetsChanged(
            xOffset: Float,
            yOffset: Float,
            xOffsetStep: Float,
            yOffsetStep: Float,
            xPixelOffset: Int,
            yPixelOffset: Int,
        ) {
            if (!scrollingEnabled) return
            wallpaperXOffset = xOffset.coerceIn(0f, 1f)
            val frame = currentFrameBitmap?.takeIf {
                currentFrameIndex == currentIndex && frameMatchesSurface(it)
            }
            if (frame != null && visible) {
                postFrame(currentIndex, frame, allowHidden = false)
            }
        }

        // Enables launcher offset callbacks only while the user has requested scrolling.
        private fun updateScrollingMode(activeStore: WakeWallStore) {
            val enabled = activeStore.wallpaperScrolling
            if (scrollingEnabled == enabled) return
            scrollingEnabled = enabled
            wallpaperXOffset = .5f
            setOffsetNotificationsEnabled(enabled)
        }

        // Detects a real display-off transition without rotating when another app covers the wallpaper.
        private fun deviceIsTurningOff(): Boolean {
            val displayState = displayManager
                .getDisplay(Display.DEFAULT_DISPLAY)
                ?.state
            return !powerManager.isInteractive ||
                displayState == Display.STATE_OFF ||
                displayState == Display.STATE_DOZE ||
                displayState == Display.STATE_DOZE_SUSPEND
        }

        override fun onSurfaceChanged(
            holder: SurfaceHolder,
            format: Int,
            width: Int,
            height: Int,
        ) {
            super.onSurfaceChanged(holder, format, width, height)
            if (unlockedStore() == null) {
                postBootFrame(allowHidden = true)
                return
            }
            scheduleRebuild()
        }

        // Keeps the earliest rebuild queued so the next wallpaper is ready before screen-off.
        private fun scheduleRebuild() {
            if (rebuildScheduled) return
            rebuildScheduled = true
            handler.post(rebuildRunner)
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            visible = false
            handler.removeCallbacks(rebuildRunner)
            rebuildScheduled = false
            super.onSurfaceDestroyed(holder)
        }

        // Switches to the prepared wallpaper as the screen begins turning off.
        private fun handleScreenOff() {
            if (screenOffHandled) return
            screenOffHandled = true
            handler.removeCallbacks(rebuildRunner)
            rebuildScheduled = false

            val activeStore = unlockedStore()
            if (activeStore == null) {
                postBootFrame(allowHidden = true)
                return
            }

            val nextIndex = activeStore.advanceForScreenOff(currentIndex)
            val prepared = preparedBitmap?.takeIf {
                preparedIndex == nextIndex &&
                    frameMatchesSurface(it)
            }
            val currentFrame = currentFrameBitmap?.takeIf {
                currentFrameIndex == nextIndex && frameMatchesSurface(it)
            }
            val drawSucceeded = postFrame(
                index = nextIndex,
                bitmap = prepared ?: currentFrame,
                allowHidden = true,
            )

            if (prepared != null) promotePreparedFrame(nextIndex)
            currentIndex = nextIndex
            activeStore.recordScreenOffDraw(
                drawSucceeded = drawSucceeded,
                usedPreparedFrame = prepared != null,
            )
            scheduleNextFramePreparation()
        }

        // Reposts the retained frame before Android reveals the wallpaper surface.
        private fun restoreCurrentFrame() {
            val activeStore = unlockedStore()
            if (activeStore == null) {
                postBootFrame(allowHidden = true)
                return
            }
            currentIndex = activeStore.index
            val currentFrame = currentFrameBitmap?.takeIf {
                currentFrameIndex == currentIndex && frameMatchesSurface(it)
            }
            if (currentFrame != null) {
                postFrame(
                    index = currentIndex,
                    bitmap = currentFrame,
                    allowHidden = true,
                )
            }
        }

        // Refreshes this wallpaper surface and keeps its next image ready.
        private fun redrawCurrentAndPrepare() {
            val activeStore = unlockedStore()
            if (activeStore == null) {
                postBootFrame(allowHidden = true)
                return
            }
            currentIndex = activeStore.index
            val currentFrame = ensureCurrentFrame(activeStore)
            val drawSucceeded = postFrame(
                index = currentIndex,
                bitmap = currentFrame,
                allowHidden = screenOffHandled || deviceIsTurningOff(),
            )
            if (!drawSucceeded) postBootFrame(allowHidden = true)
            scheduleNextFramePreparation()
        }

        // Prepares the following wallpaper away from Android's wallpaper event thread.
        private fun scheduleNextFramePreparation() {
            if (destroyed) return
            val activeStore = unlockedStore() ?: return
            val frame = surfaceHolder.surfaceFrame
            if (frame.width() <= 0 || frame.height() <= 0) return

            val existing = preparedBitmap
            if (preparedIndex >= 0 &&
                preparedIndex != currentIndex &&
                existing != null &&
                !existing.isRecycled &&
                existing.width == frameBufferWidth(frame.width()) &&
                existing.height == frame.height()
            ) {
                return
            }
            if (preparingIndex >= 0) return

            val nextIndex = activeStore.nextIndex(currentIndex)
            if (nextIndex == currentIndex) {
                preparedIndex = -1
                return
            }
            val width = frameBufferWidth(frame.width())
            val height = frame.height()
            val reusable = existing?.takeIf {
                !it.isRecycled &&
                    it.width == width &&
                    it.height == height
            }
            if (existing !== reusable) {
                preparedBitmap?.takeUnless { it.isRecycled }?.recycle()
            }
            preparedBitmap = null
            preparedIndex = -1

            val sourceIndex = currentIndex
            val generation = ++preparationGeneration
            preparingIndex = nextIndex
            preparationExecutor.execute {
                val bitmap = reusable ?: runCatching {
                    Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                }.getOrNull()
                val rendered = bitmap?.let {
                    runCatching { drawWallpaper(Canvas(it), nextIndex, activeStore) }.isSuccess
                } == true
                handler.post {
                    val stillNeeded = !destroyed &&
                        generation == preparationGeneration &&
                        currentIndex == sourceIndex &&
                        rendered
                    if (stillNeeded) {
                        preparedBitmap?.takeUnless { it.isRecycled }?.recycle()
                        preparedBitmap = bitmap
                        preparedIndex = nextIndex
                    } else {
                        bitmap?.takeUnless { it.isRecycled }?.recycle()
                    }
                    if (generation == preparationGeneration) preparingIndex = -1
                }
            }
        }

        // Keeps the newly selected wallpaper cached while reusing the previous buffer for next.
        private fun promotePreparedFrame(index: Int) {
            val previousCurrent = currentFrameBitmap
            currentFrameBitmap = preparedBitmap
            currentFrameIndex = index
            preparedBitmap = previousCurrent
            preparedIndex = -1
        }

        // Renders the current wallpaper once so wake and surface recreation only copy pixels.
        private fun ensureCurrentFrame(activeStore: WakeWallStore): Bitmap? {
            val frame = surfaceHolder.surfaceFrame
            if (frame.width() <= 0 || frame.height() <= 0) return null

            val existing = currentFrameBitmap
            if (currentFrameIndex == currentIndex &&
                existing != null &&
                !existing.isRecycled &&
                existing.width == frameBufferWidth(frame.width()) &&
                existing.height == frame.height()
            ) {
                return existing
            }

            val bitmap = existing
                ?.takeIf {
                    !it.isRecycled &&
                        it.width == frameBufferWidth(frame.width()) &&
                        it.height == frame.height()
                }
                ?: runCatching {
                    Bitmap.createBitmap(frameBufferWidth(frame.width()), frame.height(), Bitmap.Config.ARGB_8888)
                }.getOrNull()
                ?: return null
            drawWallpaper(Canvas(bitmap), currentIndex, activeStore)
            if (bitmap !== existing) {
                currentFrameBitmap?.takeUnless { it.isRecycled }?.recycle()
            }
            currentFrameBitmap = bitmap
            currentFrameIndex = currentIndex
            return bitmap
        }

        private fun invalidateFrames() {
            preparationGeneration += 1
            preparingIndex = -1
            currentFrameBitmap?.takeUnless { it.isRecycled }?.recycle()
            currentFrameBitmap = null
            currentFrameIndex = -1
            preparedBitmap?.takeUnless { it.isRecycled }?.recycle()
            preparedBitmap = null
            preparedIndex = -1
        }

        private fun frameMatchesSurface(bitmap: Bitmap): Boolean {
            val frame = surfaceHolder.surfaceFrame
            return !bitmap.isRecycled &&
                frame.width() > 0 &&
                frame.height() > 0 &&
                bitmap.width == frameBufferWidth(frame.width()) &&
                bitmap.height == frame.height()
        }

        private fun frameBufferWidth(surfaceWidth: Int): Int =
            if (scrollingEnabled) {
                (surfaceWidth * WakeWallStore.SCROLLING_WIDTH_MULTIPLIER).roundToInt()
            } else {
                surfaceWidth
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
                canvas = lockSurfaceCanvas(useHardware = bitmap != null)
                if (canvas != null) {
                    if (bitmap != null) {
                        drawCachedFrame(canvas, bitmap, index)
                    } else {
                        val activeStore = unlockedStore()
                        if (activeStore != null) {
                            drawWallpaper(canvas, index, activeStore)
                        } else {
                            if (!drawBootFrame(canvas)) return false
                        }
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

        // Uses the last saved frame while Android is still locked after a restart.
        private fun postBootFrame(allowHidden: Boolean): Boolean {
            if (!visible && !allowHidden) return false
            var canvas: Canvas? = null
            var drewFrame = false
            try {
                canvas = lockSurfaceCanvas(useHardware = true)
                if (canvas != null) drewFrame = drawBootFrame(canvas)
            } catch (_: Exception) {
                drewFrame = false
            } finally {
                val posted = canvas != null && runCatching {
                    surfaceHolder.unlockCanvasAndPost(canvas)
                }.isSuccess
                return drewFrame && posted
            }
        }

        private fun drawBootFrame(canvas: Canvas): Boolean {
            val file = bootFrameStore.frameFile() ?: return false
            val bitmap = BitmapFactory.decodeFile(file.absolutePath) ?: return false
            return try {
                val width = canvas.width.toFloat()
                val height = canvas.height.toFloat()
                val scale = max(width / bitmap.width, height / bitmap.height)
                val drawnWidth = bitmap.width * scale
                val drawnHeight = bitmap.height * scale
                canvas.drawColor(Color.BLACK)
                canvas.drawBitmap(
                    bitmap,
                    null,
                    RectF(
                        (width - drawnWidth) / 2f,
                        (height - drawnHeight) / 2f,
                        (width + drawnWidth) / 2f,
                        (height + drawnHeight) / 2f,
                    ),
                    Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG),
                )
                true
            } finally {
                bitmap.recycle()
            }
        }

        // Copies the visible launcher viewport from a prepared wide frame.
        private fun drawCachedFrame(canvas: Canvas, bitmap: Bitmap, index: Int) {
            if (!scrollingEnabled || bitmap.width <= canvas.width) {
                canvas.drawBitmap(bitmap, 0f, 0f, null)
                return
            }
            val displayMode = unlockedStore()?.displayMode(index) ?: "fill"
            // Keeps bordered compositions centred instead of exposing uneven edges.
            val visibleOffset = if (displayMode == "fill") {
                wallpaperXOffset
            } else {
                .5f
            }
            val left = ((bitmap.width - canvas.width) * visibleOffset)
                .toInt()
                .coerceIn(0, bitmap.width - canvas.width)
            canvas.drawBitmap(
                bitmap,
                Rect(left, 0, left + canvas.width, bitmap.height),
                RectF(0f, 0f, canvas.width.toFloat(), canvas.height.toFloat()),
                null,
            )
        }

        // Copies complete cached frames with the GPU when available.
        private fun lockSurfaceCanvas(useHardware: Boolean): Canvas? {
            if (useHardware && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                runCatching { surfaceHolder.lockHardwareCanvas() }
                    .getOrNull()
                    ?.let { return it }
            }
            return surfaceHolder.lockCanvas()
        }

        // Draws either a selected photo or one of the bundled samples.
        private fun drawWallpaper(canvas: Canvas, index: Int, activeStore: WakeWallStore) {
            val entry = activeStore.wallpaperAt(index)
            if (entry == null) {
                canvas.drawColor(Color.BLACK)
                return
            }
            if (!entry.startsWith("sample:")) {
                if (!drawPhoto(canvas, index, entry, activeStore)) canvas.drawColor(Color.BLACK)
                return
            }
            drawSample(canvas, entry.removePrefix("sample:").toIntOrNull() ?: index, index, activeStore)
        }

        private fun drawPhoto(
            canvas: Canvas,
            index: Int,
            uriValue: String,
            activeStore: WakeWallStore,
        ): Boolean {
            val width = canvas.width.toFloat()
            val height = canvas.height.toFloat()
            val rendered = activeStore.wallpaperRenderFile(index, scrollingEnabled)?.let {
                BitmapFactory.decodeFile(it.absolutePath)
            }
            if (rendered != null && rendered.width > 0 && rendered.height > 0) {
                val renderedRatio = rendered.width.toFloat() / rendered.height
                val canvasRatio = width / height
                if (kotlin.math.abs(renderedRatio - canvasRatio) < .035f) {
                    val scale = max(width / rendered.width, height / rendered.height)
                    val drawnWidth = rendered.width * scale
                    val drawnHeight = rendered.height * scale
                    canvas.drawColor(Color.BLACK)
                    canvas.drawBitmap(
                        rendered,
                        null,
                        RectF(
                            (width - drawnWidth) / 2f,
                            (height - drawnHeight) / 2f,
                            (width + drawnWidth) / 2f,
                            (height + drawnHeight) / 2f,
                        ),
                        Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG),
                    )
                    rendered.recycle()
                    return true
                }
                rendered.recycle()
            }
            val crop = activeStore.crop(index)
            val displayMode = activeStore.displayMode(index)
            val bitmap = decodePhoto(
                uriValue,
                canvas.width,
                canvas.height,
                crop.scale,
                displayMode,
                activeStore,
            ) ?: return false
            canvas.drawColor(
                if (displayMode == "fit") activeStore.fitBackgroundColor(index)
                else Color.rgb(32, 33, 36),
            )
            if (displayMode == "blur") WakeWallBlurRenderer.draw(canvas, bitmap, width, height)
            canvas.save()

            val scale = if (displayMode == "fit" || displayMode == "blur") {
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
            canvas.drawBitmap(
                bitmap,
                null,
                destination,
                Paint(
                    Paint.ANTI_ALIAS_FLAG or
                        Paint.FILTER_BITMAP_FLAG or
                        Paint.DITHER_FLAG,
                ),
            )
            canvas.restore()
            bitmap.recycle()
            return true
        }

        // Loads a camera photo near the screen size and respects its saved orientation.
        private fun decodePhoto(
            uriValue: String,
            targetWidth: Int,
            targetHeight: Int,
            cropScale: Float,
            displayMode: String,
            activeStore: WakeWallStore,
        ): Bitmap? {
            return runCatching {
                val localFile = activeStore.localFile(uriValue)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val source = if (localFile != null) {
                        ImageDecoder.createSource(localFile)
                    } else {
                        ImageDecoder.createSource(contentResolver, android.net.Uri.parse(uriValue))
                    }
                    ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                        val qualityScale = cropScale.coerceIn(1f, 4f)
                        val widthScale =
                            targetWidth * qualityScale / info.size.width.toFloat()
                        val heightScale =
                            targetHeight * qualityScale / info.size.height.toFloat()
                        val scale = (
                            if (displayMode == "fit" || displayMode == "blur") {
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
                    activeStore.openImage(uriValue)?.use(BitmapFactory::decodeStream)
                }
            }.getOrNull()
        }

        // Builds one of the bundled sample wallpapers directly onto the surface.
        private fun drawSample(
            canvas: Canvas,
            sampleIndex: Int,
            cropIndex: Int,
            activeStore: WakeWallStore,
        ) {
            val width = canvas.width.toFloat()
            val height = canvas.height.toFloat()
            val crop = activeStore.crop(cropIndex)
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
