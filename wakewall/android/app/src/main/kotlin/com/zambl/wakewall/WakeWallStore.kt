package com.zambl.wakewall

import android.content.Context
import android.content.ContentResolver
import android.provider.DocumentsContract
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Point
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.util.Size
import org.json.JSONArray
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.random.Random

class WakeWallStore(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("wakewall", Context.MODE_PRIVATE)

    var paused: Boolean
        get() = prefs.getBoolean("paused", false)
        set(value) = prefs.edit().putBoolean("paused", value).apply()

    var shuffle: Boolean
        get() = prefs.getBoolean("shuffle", true)
        set(value) = prefs.edit().putBoolean("shuffle", value).apply()

    var fit: String
        get() = prefs.getString("fit", "cropToFill") ?: "cropToFill"
        set(value) = prefs.edit().putString("fit", value).apply()

    var photoSource: String
        get() = prefs.getString("photo_source", "askEveryTime") ?: "askEveryTime"
        set(value) = prefs.edit().putString("photo_source", value).apply()

    val wallpapers: List<String>
        get() {
            val saved = prefs.getString("wallpapers", null)
            if (saved == null) return emptyList()
            val array = JSONArray(saved)
            return List(array.length()) { array.getString(it) }
        }

    val wallpaperCount: Int
        get() = wallpapers.size

    val index: Int
        get() = if (wallpaperCount == 0) 0 else prefs.getInt("index", 0).mod(wallpaperCount)

    fun wallpaperAt(index: Int): String? = wallpapers.getOrNull(index)

    fun updateSettings(paused: Boolean, shuffle: Boolean, fit: String) {
        prefs.edit()
            .putBoolean("paused", paused)
            .putBoolean("shuffle", shuffle)
            .putString("fit", fit)
            .apply()
    }

    fun updatePhotoSource(source: String) {
        photoSource = source
    }

    fun addImages(uris: List<Uri>): ImportSummary {
        val updated = wallpapers.toMutableList()
        val failed = mutableListOf<FailedImport>()
        val imported = uris.mapNotNull { uri ->
            val outcome = importIntoAppStorage(uri)
            outcome.value ?: run {
                outcome.failure?.let(failed::add)
                null
            }
        }
        imported.forEach(updated::add)
        saveWallpapers(updated)
        return ImportSummary(imported.size, uris.size - imported.size, failed)
    }

    // Stores clean JPEGs created by Flutter's independent fallback decoder.
    fun addNormalizedImages(images: List<NormalizedImport>): Int {
        val updated = wallpapers.toMutableList()
        var imported = 0
        images.forEach { image ->
            val id = "${UUID.randomUUID()}.jpg"
            val directory = File(appContext.filesDir, "wallpapers").apply { mkdirs() }
            val destination = File(directory, id)
            val saved = runCatching {
                destination.writeBytes(image.bytes)
                imageDimensions(destination) != null
            }.getOrDefault(false)
            if (!saved) {
                destination.delete()
                return@forEach
            }
            val value = "$LOCAL_PREFIX$id"
            prefs.edit().putString("name_${value.hashCode()}", image.name).apply()
            updated.add(value)
            imported++
        }
        saveWallpapers(updated)
        return imported
    }

    fun removeWallpaper(index: Int) {
        val updated = wallpapers.toMutableList()
        if (index !in updated.indices) return
        val selected = wallpaperAt(this.index)
        val removed = updated.removeAt(index)
        localFile(removed)?.delete()
        deleteCachedPreviews(removed)
        saveWallpapers(updated)
        val nextIndex = updated.indexOf(selected).takeIf { it >= 0 }
            ?: index.coerceAtMost((updated.size - 1).coerceAtLeast(0))
        prefs.edit().putInt("index", nextIndex).apply()
    }

    fun moveWallpaper(oldIndex: Int, newIndex: Int) {
        val updated = wallpapers.toMutableList()
        if (oldIndex !in updated.indices || newIndex !in updated.indices || oldIndex == newIndex) return
        val selected = wallpaperAt(index)
        updated.add(newIndex, updated.removeAt(oldIndex))
        saveWallpapers(updated)
        prefs.edit().putInt("index", updated.indexOf(selected).coerceAtLeast(0)).apply()
    }

    fun advance(trigger: String): Int {
        val current = index
        val next = nextIndex(current, allowWhenPaused = trigger == "manual")
        commitIndex(next, trigger)
        return next
    }

    // Chooses the next wallpaper using the selected order and pause setting.
    fun nextIndex(current: Int, allowWhenPaused: Boolean = false): Int {
        if (paused && !allowWhenPaused || wallpaperCount <= 1) return current
        return if (shuffle) {
            var candidate = current
            while (candidate == current) candidate = Random.nextInt(wallpaperCount)
            candidate
        } else {
            (current + 1).mod(wallpaperCount)
        }
    }

    fun commitIndex(next: Int, trigger: String) {
        val current = index
        if (next == current || next !in wallpapers.indices) return
        prefs.edit()
            .putInt("index", next)
            .putString("last_trigger", trigger)
            .putLong("last_change_at", System.currentTimeMillis())
            .putInt("change_count", prefs.getInt("change_count", 0) + 1)
            .apply()
    }

    // Saves the new wallpaper and its screen-off result in one update.
    fun commitScreenOff(next: Int, drawSucceeded: Boolean, usedPreparedFrame: Boolean) {
        val current = index
        val now = System.currentTimeMillis()
        val editor = prefs.edit()
            .putString("last_event", "screen_off")
            .putLong("last_event_at", now)
            .putInt("screen_off_count", prefs.getInt("screen_off_count", 0) + 1)
            .putString("last_draw_reason", "screen_off_prepare")
            .putBoolean("last_draw_succeeded", drawSucceeded)
            .putBoolean("last_screen_off_used_prepared_frame", usedPreparedFrame)
            .putInt(
                "screen_off_${if (usedPreparedFrame) "prepared" else "fallback"}_count",
                prefs.getInt("screen_off_${if (usedPreparedFrame) "prepared" else "fallback"}_count", 0) + 1,
            )
            .putLong("last_draw_at", now)
            .putInt(
                "screen_off_prepare_${if (drawSucceeded) "success" else "failure"}_count",
                prefs.getInt("screen_off_prepare_${if (drawSucceeded) "success" else "failure"}_count", 0) + 1,
            )

        if (next != current && next in wallpapers.indices) {
            editor
                .putInt("index", next)
                .putString("last_trigger", "screen_off")
                .putLong("last_change_at", now)
                .putInt("change_count", prefs.getInt("change_count", 0) + 1)
        }
        editor.apply()
    }

    fun recordEvent(event: String) {
        prefs.edit()
            .putString("last_event", event)
            .putLong("last_event_at", System.currentTimeMillis())
            .putInt("${event}_count", prefs.getInt("${event}_count", 0) + 1)
            .apply()
    }

    fun setCrop(index: Int, scale: Double, offsetX: Double, offsetY: Double) {
        val key = cropKey(index)
        prefs.edit()
            .putFloat("${key}_scale", scale.toFloat())
            .putFloat("${key}_x", offsetX.toFloat())
            .putFloat("${key}_y", offsetY.toFloat())
            .apply()
    }

    fun crop(index: Int): CropTransform {
        val key = cropKey(index)
        return CropTransform(
            scale = prefs.getFloat("${key}_scale", 1f),
            offsetX = prefs.getFloat("${key}_x", 0f),
            offsetY = prefs.getFloat("${key}_y", 0f),
        )
    }

    fun configuration(): Map<String, Any> {
        migrateExternalImages()
        return mapOf(
            "index" to index,
            "paused" to paused,
            "shuffle" to shuffle,
            "fit" to fit,
            "photoSource" to photoSource,
            "wallpapers" to wallpapers.mapIndexed(::wallpaperMap),
        )
    }

    fun diagnostics(): Map<String, Any> = mapOf(
        "status" to if (paused) "Paused" else "Ready",
        "current_wallpaper" to if (wallpaperCount == 0) "None" else "${index + 1} of $wallpaperCount",
        "last_event" to (prefs.getString("last_event", "None yet") ?: "None yet"),
        "last_trigger" to (prefs.getString("last_trigger", "None yet") ?: "None yet"),
        "screen_on_count" to prefs.getInt("screen_on_count", 0),
        "screen_off_count" to prefs.getInt("screen_off_count", 0),
        "change_count" to prefs.getInt("change_count", 0),
        "last_draw_reason" to (prefs.getString("last_draw_reason", "None yet") ?: "None yet"),
        "last_draw_succeeded" to prefs.getBoolean("last_draw_succeeded", false),
        "screen_off_draw_success_count" to prefs.getInt("screen_off_prepare_success_count", 0),
        "screen_off_draw_failure_count" to prefs.getInt("screen_off_prepare_failure_count", 0),
        "last_screen_off_used_prepared_frame" to prefs.getBoolean("last_screen_off_used_prepared_frame", false),
        "screen_off_prepared_frame_count" to prefs.getInt("screen_off_prepared_count", 0),
        "screen_off_fallback_render_count" to prefs.getInt("screen_off_fallback_count", 0),
        "last_import_diagnostics" to (prefs.getString("last_import_diagnostics", "None yet") ?: "None yet"),
    )

    private fun saveWallpapers(wallpapers: List<String>) {
        prefs.edit().putString("wallpapers", JSONArray(wallpapers).toString()).apply()
    }

    // Moves older picker-based entries into the same reliable private storage.
    private fun migrateExternalImages() {
        var changed = false
        val migrated = wallpapers.mapNotNull { value ->
            if (value.startsWith(SAMPLE_PREFIX)) {
                changed = true
                null
            } else if (value.startsWith(LOCAL_PREFIX) && prefs.getInt("image_format_version", 0) < 1) {
                normalizeLocalImage(value)?.also { changed = true } ?: value
            } else if (value.startsWith(LOCAL_PREFIX)) {
                value
            } else {
                importIntoAppStorage(Uri.parse(value)).value?.also { changed = true } ?: value
            }
        }
        if (changed) saveWallpapers(migrated)
        prefs.edit().putInt("image_format_version", 1).apply()
    }

    private fun cropKey(index: Int): String = "crop_${wallpaperAt(index)?.hashCode() ?: index}"

    // Creates the small preview Flutter displays without passing the full photo.
    private fun wallpaperMap(index: Int, value: String): Map<String, Any> {
        val result = mutableMapOf<String, Any>("crop" to crop(index).asMap())
        if (value.startsWith(SAMPLE_PREFIX)) {
            result["sampleIndex"] = value.removePrefix(SAMPLE_PREFIX).toIntOrNull() ?: 0
            return result
        }

        result["uri"] = value
        result["name"] = displayName(value)
        imageDimensions(value)?.let { (width, height) ->
            result["imageWidth"] = width
            result["imageHeight"] = height
        }
        thumbnail(value)?.let { result["thumbnail"] = it }
        cachedPreview(value, LARGE_PREVIEW_EDGE, 92, "large")?.let { result["preview"] = it }
        return result
    }

    private fun displayName(value: String): String {
        if (value.startsWith(LOCAL_PREFIX)) {
            return prefs.getString("name_${value.hashCode()}", "Photo") ?: "Photo"
        }
        val uri = Uri.parse(value)
        return runCatching {
            appContext.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
        }.getOrNull() ?: "Photo"
    }

    private fun thumbnail(value: String): ByteArray? =
        cachedPreview(value, SMALL_PREVIEW_EDGE, 82, "small")

    // Creates a full-aspect preview without permanently cropping away content.
    private fun fullAspectPreview(value: String, maxEdge: Float): Bitmap? {
        val file = localFile(value)
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && file != null) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
                    val scale = (maxEdge / max(info.size.width, info.size.height).toFloat())
                        .coerceAtMost(1f)
                    decoder.setTargetSize(
                        max(1, (info.size.width * scale).roundToInt()),
                        max(1, (info.size.height * scale).roundToInt()),
                    )
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                }
            } else {
                openImage(value)?.use(BitmapFactory::decodeStream)
            }
        }.getOrNull()
    }

    // Reuses previews from private storage instead of decoding photos on every tap.
    private fun cachedPreview(value: String, maxEdge: Float, quality: Int, suffix: String): ByteArray? {
        val directory = File(appContext.cacheDir, "wallpaper_previews").apply { mkdirs() }
        val file = File(directory, "${value.hashCode()}_$suffix.jpg")
        if (file.exists()) return runCatching { file.readBytes() }.getOrNull()
        val bitmap = fullAspectPreview(value, maxEdge) ?: return null
        val saved = runCatching {
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it) }
        }.getOrDefault(false)
        bitmap.recycle()
        return if (saved) runCatching { file.readBytes() }.getOrNull() else null
    }

    private fun deleteCachedPreviews(value: String) {
        val directory = File(appContext.cacheDir, "wallpaper_previews")
        listOf("small", "large").forEach { File(directory, "${value.hashCode()}_$it.jpg").delete() }
    }

    private fun imageDimensions(value: String): Pair<Int, Int>? {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        return runCatching {
            openImage(value)?.use { BitmapFactory.decodeStream(it, null, options) }
            if (options.outWidth > 0 && options.outHeight > 0) {
                options.outWidth to options.outHeight
            } else {
                null
            }
        }.getOrNull()
    }

    // Copies picker photos into WakeWall so temporary gallery access cannot expire.
    private fun importIntoAppStorage(uri: Uri): ImportOutcome {
        val name = displayName(uri.toString())
        val id = "${UUID.randomUUID()}.jpg"
        val directory = File(appContext.filesDir, "wallpapers").apply { mkdirs() }
        val destination = File(directory, id)
        val normalized = normalizeImage(uri, destination)
        prefs.edit().putString("last_import_diagnostics", "$name: ${normalized.diagnostics}").apply()
        if (!normalized.saved) {
            destination.delete()
            return ImportOutcome(
                failure = normalized.fallbackBytes?.let { FailedImport(name, it, normalized.diagnostics) },
            )
        }
        val value = "$LOCAL_PREFIX$id"
        prefs.edit().putString("name_${value.hashCode()}", name).apply()
        return ImportOutcome(value = value)
    }

    // Tries every automatic provider access route before giving up on a selection.
    private fun normalizeImage(uri: Uri, destination: File): NormalizeResult {
        val source = File.createTempFile("wakewall_import_", ".image", appContext.cacheDir)
        val diagnostics = mutableListOf<String>()
        var fallbackBytes: ByteArray? = null
        var expectedSize: Pair<Int, Int>? = null
        return try {
            val accessRoutes = listOf<Pair<String, (File) -> Boolean>>(
                "original_descriptor" to { copyFromOriginalFileDescriptor(uri, it) },
                "file_descriptor" to { copyFromFileDescriptor(uri, it) },
                "asset_descriptor" to { copyFromAssetDescriptor(uri, it) },
                "input_stream" to { copyFromInputStream(uri, it) },
            )
            accessRoutes.forEach { (label, copy) ->
                source.delete()
                val copied = copy(source)
                diagnostics.add("$label:${if (copied) source.length() else "unavailable"}")
                if (!copied || source.length() <= 0) return@forEach
                if (source.length() > (fallbackBytes?.size ?: 0)) {
                    fallbackBytes = runCatching { source.readBytes() }.getOrNull()
                }
                val dimensions = imageDimensions(source)
                if (expectedSize == null) expectedSize = dimensions
                val decoded = decodeNormalizedBitmap(source)
                    ?.takeIf { isUsableBitmap(it, dimensions ?: expectedSize) }
                if (decoded != null && saveAsJpeg(decoded, destination)) {
                    diagnostics.add("$label:decoded")
                    return NormalizeResult(true, fallbackBytes, diagnostics.joinToString(", "))
                }
                diagnostics.add("$label:decode_failed")
            }

            val mediaUri = equivalentMediaStoreUri(uri)
            if (mediaUri != null && mediaUri != uri) {
                val localRoutes = listOf<Pair<String, (File) -> Boolean>>(
                    "media_original_descriptor" to { copyFromOriginalFileDescriptor(mediaUri, it) },
                    "media_file_descriptor" to { copyFromFileDescriptor(mediaUri, it) },
                    "media_asset_descriptor" to { copyFromAssetDescriptor(mediaUri, it) },
                    "media_input_stream" to { copyFromInputStream(mediaUri, it) },
                )
                localRoutes.forEach { (label, copy) ->
                    source.delete()
                    val copied = copy(source)
                    diagnostics.add("$label:${if (copied) source.length() else "unavailable"}")
                    if (!copied || source.length() <= 0) return@forEach
                    if (source.length() > (fallbackBytes?.size ?: 0)) {
                        fallbackBytes = runCatching { source.readBytes() }.getOrNull()
                    }
                    val dimensions = imageDimensions(source)
                    if (expectedSize == null) expectedSize = dimensions
                    val decoded = decodeNormalizedBitmap(source)
                        ?.takeIf { isUsableBitmap(it, dimensions ?: expectedSize) }
                    if (decoded != null && saveAsJpeg(decoded, destination)) {
                        diagnostics.add("$label:decoded")
                        return NormalizeResult(true, fallbackBytes, diagnostics.joinToString(", "))
                    }
                    diagnostics.add("$label:decode_failed")
                }
            } else {
                diagnostics.add("media_equivalent:unavailable")
            }

            val transformed = loadProviderTransformedImage(uri, expectedSize)
            if (transformed != null && saveAsJpeg(transformed, destination)) {
                diagnostics.add("provider_transformed:decoded")
                return NormalizeResult(true, fallbackBytes, diagnostics.joinToString(", "))
            }
            diagnostics.add("provider_transformed:failed")

            val rendered = loadProviderRenderedImage(uri, expectedSize)
            if (rendered != null && saveAsJpeg(rendered, destination)) {
                diagnostics.add("provider_thumbnail:decoded")
                return NormalizeResult(true, fallbackBytes, diagnostics.joinToString(", "))
            }
            diagnostics.add("provider_thumbnail:failed")
            NormalizeResult(false, fallbackBytes, diagnostics.joinToString(", "))
        } finally {
            source.delete()
        }
    }

    private fun copyFromFileDescriptor(uri: Uri, destination: File): Boolean = runCatching {
        appContext.contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
            FileInputStream(descriptor.fileDescriptor).use { input ->
                destination.outputStream().use(input::copyTo)
            }
        } != null
    }.getOrDefault(false)

    private fun copyFromOriginalFileDescriptor(uri: Uri, destination: File): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return runCatching {
            appContext.contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
                MediaStore.getOriginalMediaFormatFileDescriptor(appContext, descriptor).use { original ->
                    FileInputStream(original.fileDescriptor).use { input ->
                        destination.outputStream().use(input::copyTo)
                    }
                }
            } != null
        }.getOrDefault(false)
    }

    private fun equivalentMediaStoreUri(uri: Uri): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            !DocumentsContract.isDocumentUri(appContext, uri)
        ) {
            return null
        }
        return runCatching { MediaStore.getMediaUri(appContext, uri) }.getOrNull()
    }

    private fun copyFromAssetDescriptor(uri: Uri, destination: File): Boolean = runCatching {
        appContext.contentResolver.openAssetFileDescriptor(uri, "r")?.use { descriptor ->
            descriptor.createInputStream().use { input ->
                destination.outputStream().use(input::copyTo)
            }
        } != null
    }.getOrDefault(false)

    private fun copyFromInputStream(uri: Uri, destination: File): Boolean = runCatching {
        appContext.contentResolver.openInputStream(uri)?.use { input ->
            destination.outputStream().use(input::copyTo)
        } != null
    }.getOrDefault(false)

    // Uses Android's strict decoder so incomplete pixel data is never saved.
    private fun decodeNormalizedBitmap(source: File): Bitmap? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            runCatching {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(source)) { decoder, info, _ ->
                    val scale = (MAX_IMAGE_EDGE / max(info.size.width, info.size.height).toFloat())
                        .coerceAtMost(1f)
                    decoder.setTargetSize(
                        max(1, (info.size.width * scale).roundToInt()),
                        max(1, (info.size.height * scale).roundToInt()),
                    )
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                }
            }.getOrNull()
        } else {
            decodeWithBitmapFactory(source)
        }
    }

    // Asks the photo provider for a complete rendered image instead of raw bytes.
    private fun loadProviderTransformedImage(uri: Uri, expectedSize: Pair<Int, Int>?): Bitmap? {
        return providerRenderSizes(expectedSize).firstNotNullOfOrNull { size ->
            val rendered = File.createTempFile("wakewall_rendered_", ".image", appContext.cacheDir)
            try {
                val options = Bundle().apply {
                    putParcelable(ContentResolver.EXTRA_SIZE, Point(size.width, size.height))
                }
                val copied = runCatching {
                    appContext.contentResolver
                        .openTypedAssetFileDescriptor(uri, "image/*", options)
                        ?.use { descriptor ->
                            descriptor.createInputStream().use { input ->
                                rendered.outputStream().use(input::copyTo)
                            }
                        } != null
                }.getOrDefault(false)
                if (!copied) return@firstNotNullOfOrNull null
                decodeNormalizedBitmap(rendered)?.takeIf { isUsableBitmap(it, expectedSize) }
            } finally {
                rendered.delete()
            }
        }
    }

    // Lets the selected photo provider render cloud-backed or unusual images.
    private fun loadProviderRenderedImage(uri: Uri, expectedSize: Pair<Int, Int>?): Bitmap? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return providerRenderSizes(expectedSize).firstNotNullOfOrNull { size ->
            runCatching {
                appContext.contentResolver.loadThumbnail(uri, size, null)
            }.getOrNull()?.takeIf { isUsableBitmap(it, expectedSize) }
        }
    }

    // Requests provider previews at the photo's own shape instead of a huge square.
    private fun providerRenderSizes(expectedSize: Pair<Int, Int>?): List<Size> {
        val (width, height) = expectedSize ?: return listOf(Size(1440, 1440), Size(720, 720))
        return listOf(MAX_IMAGE_EDGE, 2048f, 1024f)
            .map { edge ->
                val scale = (edge / max(width, height).toFloat()).coerceAtMost(1f)
                Size(max(1, (width * scale).roundToInt()), max(1, (height * scale).roundToInt()))
            }
            .distinct()
    }

    // Rejects empty or wrongly shaped provider results before they reach storage.
    private fun isUsableBitmap(bitmap: Bitmap, expectedSize: Pair<Int, Int>?): Boolean {
        if (bitmap.width <= 0 || bitmap.height <= 0) return false
        val (expectedWidth, expectedHeight) = expectedSize ?: return true
        val expectedRatio = expectedWidth.toDouble() / expectedHeight
        val actualRatio = bitmap.width.toDouble() / bitmap.height
        return abs(actualRatio - expectedRatio) / expectedRatio < .08 ||
            abs(actualRatio - 1 / expectedRatio) / (1 / expectedRatio) < .08
    }

    private fun imageDimensions(file: File): Pair<Int, Int>? {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, options)
        return if (options.outWidth > 0 && options.outHeight > 0) {
            options.outWidth to options.outHeight
        } else {
            null
        }
    }

    // Supports older Android versions that do not provide ImageDecoder.
    private fun decodeWithBitmapFactory(source: File): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sampleSize = 1
        while (max(bounds.outWidth, bounds.outHeight) / sampleSize > MAX_IMAGE_EDGE * 2) {
            sampleSize *= 2
        }
        return runCatching {
            BitmapFactory.decodeFile(
                source.absolutePath,
                BitmapFactory.Options().apply {
                    inSampleSize = sampleSize
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                },
            )
        }.getOrNull()
    }

    private fun normalizeLocalImage(value: String): String? {
        val original = localFile(value) ?: return null
        val name = displayName(value)
        val replacement = File(original.parentFile, "${UUID.randomUUID()}.jpg")
        val decoded = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(original)) { decoder, info, _ ->
                    val scale = (MAX_IMAGE_EDGE / max(info.size.width, info.size.height).toFloat())
                        .coerceAtMost(1f)
                    decoder.setTargetSize(
                        max(1, (info.size.width * scale).roundToInt()),
                        max(1, (info.size.height * scale).roundToInt()),
                    )
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                }
            } else {
                BitmapFactory.decodeFile(original.absolutePath)
            }
        }.getOrNull() ?: return null
        if (!saveAsJpeg(decoded, replacement)) {
            replacement.delete()
            return null
        }
        original.delete()
        val replacementValue = "$LOCAL_PREFIX${replacement.name}"
        prefs.edit().putString("name_${replacementValue.hashCode()}", name).apply()
        return replacementValue
    }

    private fun saveAsJpeg(decoded: Bitmap, destination: File): Boolean {
        val flattened = Bitmap.createBitmap(decoded.width, decoded.height, Bitmap.Config.ARGB_8888)
        Canvas(flattened).apply {
            drawColor(Color.BLACK)
            drawBitmap(decoded, 0f, 0f, null)
        }
        if (decoded !== flattened) decoded.recycle()
        val saved = runCatching {
            destination.outputStream().use {
                flattened.compress(Bitmap.CompressFormat.JPEG, 94, it)
            }
        }.getOrDefault(false)
        flattened.recycle()
        return saved
    }

    fun localFile(value: String): File? {
        if (!value.startsWith(LOCAL_PREFIX)) return null
        return File(File(appContext.filesDir, "wallpapers"), value.removePrefix(LOCAL_PREFIX))
    }

    fun openImage(value: String): InputStream? {
        return localFile(value)?.inputStream() ?: appContext.contentResolver.openInputStream(Uri.parse(value))
    }

    companion object {
        private const val MAX_IMAGE_EDGE = 4096f
        private const val SMALL_PREVIEW_EDGE = 720f
        private const val LARGE_PREVIEW_EDGE = 1920f
        private const val SAMPLE_PREFIX = "sample:"
        private const val LOCAL_PREFIX = "local:"
    }
}

data class CropTransform(
    val scale: Float,
    val offsetX: Float,
    val offsetY: Float,
) {
    fun asMap(): Map<String, Float> = mapOf(
        "scale" to scale,
        "offsetX" to offsetX,
        "offsetY" to offsetY,
    )
}

data class ImportSummary(
    val imported: Int,
    val failed: Int,
    val failedImports: List<FailedImport>,
)

data class FailedImport(
    val name: String,
    val bytes: ByteArray,
    val diagnostics: String,
)

data class NormalizedImport(
    val name: String,
    val bytes: ByteArray,
)

data class ImportOutcome(
    val value: String? = null,
    val failure: FailedImport? = null,
)

data class NormalizeResult(
    val saved: Boolean,
    val fallbackBytes: ByteArray?,
    val diagnostics: String,
)
