package com.zambl.wakewall

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Size
import org.json.JSONArray
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.util.UUID
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
        get() = prefs.getBoolean("shuffle", false)
        set(value) = prefs.edit().putBoolean("shuffle", value).apply()

    var fit: String
        get() = prefs.getString("fit", "cropToFill") ?: "cropToFill"
        set(value) = prefs.edit().putString("fit", value).apply()

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

    fun addImages(uris: List<Uri>) {
        val updated = wallpapers.toMutableList()
        uris.mapNotNull(::copyIntoAppStorage).forEach(updated::add)
        saveWallpapers(updated)
    }

    fun removeWallpaper(index: Int) {
        val updated = wallpapers.toMutableList()
        if (index !in updated.indices) return
        val selected = wallpaperAt(this.index)
        val removed = updated.removeAt(index)
        localFile(removed)?.delete()
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
                copyIntoAppStorage(Uri.parse(value))?.also { changed = true } ?: value
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
        thumbnail(value)?.let { result["thumbnail"] = it }
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

    private fun thumbnail(value: String): ByteArray? {
        val bitmap = runCatching {
            val localFile = localFile(value)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && localFile != null) {
                ThumbnailUtils.createImageThumbnail(localFile, Size(360, 720), null)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appContext.contentResolver.loadThumbnail(Uri.parse(value), Size(360, 720), null)
            } else {
                openImage(value)?.use(BitmapFactory::decodeStream)
            }
        }.getOrNull() ?: return null
        return ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 82, output)
            bitmap.recycle()
            output.toByteArray()
        }
    }

    // Copies picker photos into WakeWall so temporary gallery access cannot expire.
    private fun copyIntoAppStorage(uri: Uri): String? {
        val name = displayName(uri.toString())
        val id = "${UUID.randomUUID()}.jpg"
        val directory = File(appContext.filesDir, "wallpapers").apply { mkdirs() }
        val destination = File(directory, id)
        val normalized = normalizeImage(uri, destination)
        if (!normalized) {
            destination.delete()
            return null
        }
        val value = "$LOCAL_PREFIX$id"
        prefs.edit().putString("name_${value.hashCode()}", name).apply()
        return value
    }

    // Converts varied photo formats into one dependable, correctly oriented JPEG.
    private fun normalizeImage(uri: Uri, destination: File): Boolean {
        val decoded = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(appContext.contentResolver, uri)) {
                    decoder, info, _ ->
                    val scale = (MAX_IMAGE_EDGE / max(info.size.width, info.size.height).toFloat())
                        .coerceAtMost(1f)
                    decoder.setTargetSize(
                        max(1, (info.size.width * scale).roundToInt()),
                        max(1, (info.size.height * scale).roundToInt()),
                    )
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    decoder.setOnPartialImageListener { true }
                }
            } else {
                appContext.contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream)
            }
        }.getOrNull() ?: return false
        return saveAsJpeg(decoded, destination)
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
                    decoder.setOnPartialImageListener { true }
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
