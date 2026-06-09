package com.zambl.wakewall

import android.content.Context
import android.content.ContentResolver
import android.provider.DocumentsContract
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.Point
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.util.Size
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.random.Random

class WakeWallStore(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("wakewall", Context.MODE_PRIVATE)
    private val transactionStore = WakeWallTransactionStore(prefs)
    @Volatile
    private var activeWallpaperSnapshot: List<String>? = null
    private val fileStore by lazy {
        WakeWallFileStore(
            context = appContext,
            activeWallpapers = { wallpapers },
            pendingRemovals = { pendingRemovals().keys },
            pendingImports = transactionStore::pendingImports,
            clearPendingImports = transactionStore::clearImports,
            storageKey = ::storageKey,
            deleteMetadata = ::deleteMetadata,
            scrollingEnabled = { wallpaperScrolling },
            scrollingRenderSuffix = SCROLLING_RENDER_SUFFIX,
        )
    }

    init {
        cleanupExpiredRemovals()
    }

    var paused: Boolean
        get() = prefs.getBoolean("paused", false)
        set(value) = prefs.edit().putBoolean("paused", value).apply()

    var shuffle: Boolean
        get() = prefs.getBoolean("shuffle", true)
        set(value) = prefs.edit().putBoolean("shuffle", value).apply()

    var fit: String
        get() = prefs.getString("fit", "cropToFill") ?: "cropToFill"
        set(value) = prefs.edit().putString("fit", value).apply()

    var wallpaperScrolling: Boolean
        get() = prefs.getBoolean("wallpaper_scrolling", false)
        set(value) = prefs.edit().putBoolean("wallpaper_scrolling", value).apply()

    var photoSource: String
        get() = prefs.getString("photo_source", "askEveryTime") ?: "askEveryTime"
        set(value) = prefs.edit().putString("photo_source", value).apply()

    var askAlbumsAfterImport: Boolean
        get() = prefs.getBoolean("ask_albums_after_import", true)
        set(value) = prefs.edit().putBoolean("ask_albums_after_import", value).apply()

    val defaultImportAlbumIds: Set<String>
        get() = jsonArrayPreference("default_import_album_ids").toSet()

    var wallpaperSetupOffered: Boolean
        get() = prefs.getBoolean("wallpaper_setup_offered", false)
        set(value) = prefs.edit().putBoolean("wallpaper_setup_offered", value).apply()

    val wallpapers: List<String>
        get() {
            val saved = prefs.getString("wallpapers", null)
            if (saved == null) return emptyList()
            return runCatching {
                val array = JSONArray(saved)
                List(array.length()) { array.getString(it) }
            }.getOrDefault(emptyList())
        }

    val albums: List<WallpaperAlbum>
        get() = jsonArrayPreference("albums").mapNotNull { value ->
            runCatching {
                val item = JSONObject(value)
                WallpaperAlbum(item.getString("id"), item.getString("name"))
            }.getOrNull()
        }

    val activeAlbumIds: Set<String>
        get() {
            val allowed = albums.mapTo(mutableSetOf()) { it.id }
            return jsonArrayPreference("active_album_ids").filterTo(linkedSetOf()) { it in allowed }
        }

    val activeWallpapers: List<String>
        get() = activeWallpaperSnapshot ?: buildActiveWallpapers().also {
            activeWallpaperSnapshot = it
        }

    private fun buildActiveWallpapers(): List<String> {
            val selected = activeAlbumIds
            if (selected.isEmpty()) return wallpapers
            return wallpapers.filter { value ->
                val memberships = albumIds(value)
                memberships.any(selected::contains)
            }
    }

    fun refreshActiveWallpapers() {
        activeWallpaperSnapshot = null
    }

    val wallpaperCount: Int
        get() = activeWallpapers.size

    val index: Int
        get() = if (wallpaperCount == 0) 0 else prefs.getInt("index", 0).mod(wallpaperCount)

    fun wallpaperAt(index: Int): String? = activeWallpapers.getOrNull(index)

    fun createAlbum(name: String): WallpaperAlbum {
        val cleanName = name.trim().take(40)
        require(cleanName.isNotEmpty()) { "Give this album a name." }
        val album = WallpaperAlbum(UUID.randomUUID().toString(), cleanName)
        saveAlbums(albums + album)
        return album
    }

    fun renameAlbum(id: String, name: String) {
        val cleanName = name.trim().take(40)
        require(cleanName.isNotEmpty()) { "Give this album a name." }
        saveAlbums(albums.map { if (it.id == id) it.copy(name = cleanName) else it })
    }

    fun deleteAlbum(id: String) {
        saveAlbums(albums.filterNot { it.id == id })
        wallpapers.forEach { value -> saveAlbumIds(value, albumIds(value) - id) }
        saveDefaultImportAlbumIds(defaultImportAlbumIds - id)
        setActiveAlbums(activeAlbumIds - id)
    }

    fun setActiveAlbums(ids: Set<String>) {
        val allowed = albums.mapTo(mutableSetOf()) { it.id }
        val selected = ids.filterTo(linkedSetOf()) { it in allowed }
        val currentValue = wallpaperAt(index)
        prefs.edit()
            .putString("active_album_ids", JSONArray(selected.toList()).toString())
            .apply()
        refreshActiveWallpapers()
        val next = activeWallpapers.indexOf(currentValue).takeIf { it >= 0 } ?: 0
        prefs.edit().putInt("index", next).apply()
    }

    fun updateWallpaperAlbums(value: String, ids: Set<String>) {
        require(value in wallpapers) { "That wallpaper no longer exists." }
        val allowed = albums.mapTo(mutableSetOf()) { it.id }
        saveAlbumIds(value, ids.filterTo(linkedSetOf()) { it in allowed })
        val next = activeWallpapers.indexOf(value).takeIf { it >= 0 }
            ?: index.coerceAtMost((activeWallpapers.size - 1).coerceAtLeast(0))
        prefs.edit().putInt("index", next).apply()
    }

    fun updateImportAlbumPreference(ask: Boolean, ids: Set<String>) {
        askAlbumsAfterImport = ask
        saveDefaultImportAlbumIds(ids)
    }

    fun updateSettings(paused: Boolean, shuffle: Boolean, fit: String, wallpaperScrolling: Boolean) {
        prefs.edit()
            .putBoolean("paused", paused)
            .putBoolean("shuffle", shuffle)
            .putString("fit", fit)
            .putBoolean("wallpaper_scrolling", wallpaperScrolling)
            .apply()
    }

    fun updatePhotoSource(source: String) {
        photoSource = source
    }

    fun addImages(uris: List<Uri>, onProgress: (Int) -> Unit = {}): ImportSummary {
        val updated = wallpapers.toMutableList()
        val failed = mutableListOf<FailedImport>()
        val imported = uris.mapIndexedNotNull { index, uri ->
            val outcome = importIntoAppStorage(uri)
            onProgress(index + 1)
            outcome.value ?: run {
                outcome.failure?.let(failed::add)
                null
            }
        }
        imported.forEach(updated::add)
        saveWallpapers(updated)
        imported.forEach(::commitImport)
        prefs.edit().putInt("image_format_version", 1).apply()
        return ImportSummary(imported, uris.size - imported.size, failed)
    }

    // Stores clean JPEGs created by Flutter's independent fallback decoder.
    fun addNormalizedImages(images: List<NormalizedImport>): List<String> {
        val updated = wallpapers.toMutableList()
        val imported = mutableListOf<String>()
        images.forEach { image ->
            val destination = File(importStagingDirectory(), "${UUID.randomUUID()}.jpg")
            val saved = runCatching {
                destination.writeBytes(image.bytes)
                imageDimensions(destination) != null
            }.getOrDefault(false)
            if (!saved) {
                destination.delete()
                return@forEach
            }
            val value = promoteImport(destination, ".jpg") ?: return@forEach
            prefs.edit().putString(nameKey(value), image.name).apply()
            updated.add(value)
            imported.add(value)
        }
        saveWallpapers(updated)
        imported.forEach(::commitImport)
        prefs.edit().putInt("image_format_version", 1).apply()
        return imported
    }

    fun removeWallpaper(index: Int): RemovedWallpaper? {
        val updated = wallpapers.toMutableList()
        val removed = wallpaperAt(index) ?: return null
        val globalIndex = updated.indexOf(removed)
        if (globalIndex !in updated.indices) return null
        val selected = wallpaperAt(this.index)
        updated.removeAt(globalIndex)
        recordPendingRemoval(removed)
        saveWallpapers(updated)
        val nextIndex = activeWallpapers.indexOf(selected).takeIf { it >= 0 }
            ?: index.coerceAtMost((activeWallpapers.size - 1).coerceAtLeast(0))
        prefs.edit().putInt("index", nextIndex).apply()
        return RemovedWallpaper(removed, globalIndex, selected == removed)
    }

    // Restores a recently removed wallpaper before its source file is deleted.
    fun restoreWallpaper(removed: RemovedWallpaper) {
        val updated = wallpapers.toMutableList()
        if (removed.value in updated) return
        if (removed.value.startsWith(LOCAL_PREFIX) && localFile(removed.value)?.isFile != true) return
        val position = removed.index.coerceIn(0, updated.size)
        updated.add(position, removed.value)
        saveWallpapers(updated)
        cancelPendingRemoval(removed.value)
        if (removed.wasSelected) {
            prefs.edit().putInt("index", activeWallpapers.indexOf(removed.value).coerceAtLeast(0)).apply()
        }
    }

    // Permanently deletes a removed wallpaper after the Undo window closes.
    fun finalizeRemoval(value: String) {
        transactionStore.locked {
            if (value in wallpapers) {
                cancelPendingRemoval(value)
                return@locked
            }
            deleteRemovalFiles(value)
            cancelPendingRemoval(value)
        }
    }

    // Deletes expired removals left behind when the app closed during the Undo window.
    fun cleanupExpiredRemovals() {
        transactionStore.locked {
            val now = System.currentTimeMillis()
            val active = wallpapers.toSet()
            val pending = pendingRemovals()
            var changed = false
            pending.entries.removeAll { (value, deadline) ->
                when {
                    value in active -> {
                        changed = true
                        true
                    }
                    deadline <= now -> {
                        deleteRemovalFiles(value)
                        changed = true
                        true
                    }
                    else -> false
                }
            }
            if (changed) savePendingRemovals(pending)
        }
    }

    private fun deleteRemovalFiles(value: String) {
        fileStore.deleteRemovalFiles(value)
    }

    // Removes private image files left behind by older interrupted deletions.
    fun cleanupOrphanedFiles() {
        transactionStore.locked {
            fileStore.cleanupOrphanedFiles()
        }
    }

    // Deletes imports that were interrupted before they entered the wallpaper list.
    fun cleanupIncompleteImports() {
        transactionStore.locked {
            fileStore.cleanupIncompleteImports()
        }
    }

    // Clears files WakeWall can safely recreate or no longer references.
    fun cleanStorage(): Long {
        return fileStore.cleanStorage(::cleanupExpiredRemovals)
    }

    private fun recordPendingRemoval(value: String) {
        transactionStore.recordRemoval(
            value,
            System.currentTimeMillis() + REMOVAL_UNDO_WINDOW_MS,
        )
    }

    private fun cancelPendingRemoval(value: String) {
        transactionStore.cancelRemoval(value)
    }

    private fun pendingRemovals(): MutableMap<String, Long> =
        transactionStore.pendingRemovals()

    private fun savePendingRemovals(pending: Map<String, Long>) {
        transactionStore.saveRemovals(pending)
    }

    private fun recordPendingImport(value: String) {
        transactionStore.recordImport(value)
    }

    private fun commitImport(value: String) {
        transactionStore.finishImport(value)
    }

    private fun cancelPendingImport(value: String) {
        transactionStore.finishImport(value)
    }

    fun moveWallpaper(oldIndex: Int, newIndex: Int) {
        val updated = wallpapers.toMutableList()
        val visible = activeWallpapers
        if (oldIndex !in visible.indices || newIndex !in visible.indices || oldIndex == newIndex) return
        val selected = wallpaperAt(index)
        val moving = visible[oldIndex]
        val target = visible[newIndex]
        updated.remove(moving)
        val targetIndex = updated.indexOf(target)
        updated.add(if (oldIndex < newIndex) targetIndex + 1 else targetIndex, moving)
        saveWallpapers(updated)
        prefs.edit().putInt("index", activeWallpapers.indexOf(selected).coerceAtLeast(0)).apply()
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
            val seed = prefs.getInt("change_count", 0).toLong() shl 32 xor current.toLong()
            val offset = Random(seed).nextInt(wallpaperCount - 1) + 1
            (current + offset).mod(wallpaperCount)
        } else {
            (current + 1).mod(wallpaperCount)
        }
    }

    fun commitIndex(next: Int, trigger: String) {
        val current = index
        if (next == current || next !in activeWallpapers.indices) return
        prefs.edit()
            .putInt("index", next)
            .putString("last_trigger", trigger)
            .putLong("last_change_at", System.currentTimeMillis())
            .putInt("change_count", prefs.getInt("change_count", 0) + 1)
            .apply()
    }

    // Advances once even when Android has created several wallpaper engines.
    fun advanceForScreenOff(expectedCurrent: Int): Int = transactionStore.locked {
        val current = index
        if (current != expectedCurrent) return@locked current
        val next = nextIndex(current)
        if (next == current || next !in activeWallpapers.indices) return@locked current
        prefs.edit()
            .putInt("index", next)
            .putString("last_trigger", "screen_off")
            .putLong("last_change_at", System.currentTimeMillis())
            .putInt("change_count", prefs.getInt("change_count", 0) + 1)
            .apply()
        next
    }

    // Records whether this wallpaper surface displayed the shared screen-off target.
    fun recordScreenOffDraw(drawSucceeded: Boolean, usedPreparedFrame: Boolean) {
        val now = System.currentTimeMillis()
        prefs.edit()
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
            .apply()
    }

    fun recordEvent(event: String) {
        prefs.edit()
            .putString("last_event", event)
            .putLong("last_event_at", System.currentTimeMillis())
            .putInt("${event}_count", prefs.getInt("${event}_count", 0) + 1)
            .apply()
    }

    fun setCrop(index: Int, scale: Double, offsetX: Double, offsetY: Double) {
        val value = wallpaperAt(index)
        val key = cropKey(index)
        prefs.edit()
            .putFloat("${key}_scale", scale.toFloat())
            .putFloat("${key}_x", offsetX.toFloat())
            .putFloat("${key}_y", offsetY.toFloat())
            .remove("${legacyCropKey(index)}_scale")
            .remove("${legacyCropKey(index)}_x")
            .remove("${legacyCropKey(index)}_y")
            .apply()
        if (value != null) deleteCachedPreviews(value)
    }

    fun crop(index: Int): CropTransform {
        val value = wallpaperAt(index) ?: return CropTransform(1f, 0f, 0f)
        return crop(value)
    }

    private fun crop(value: String): CropTransform {
        val key = cropKey(value)
        val legacyKey = legacyCropKey(value)
        return CropTransform(
            scale = floatPreference("${key}_scale", "${legacyKey}_scale", 1f),
            offsetX = floatPreference("${key}_x", "${legacyKey}_x", 0f),
            offsetY = floatPreference("${key}_y", "${legacyKey}_y", 0f),
        )
    }

    fun configuration(): Map<String, Any> {
        migrateExternalImages()
        return state() + mapOf(
            "wallpapers" to activeWallpapers.mapIndexed(::wallpaperMap),
            "albums" to albums.map(WallpaperAlbum::asMap),
            "activeAlbumIds" to activeAlbumIds.toList(),
            "askAlbumsAfterImport" to askAlbumsAfterImport,
            "defaultImportAlbumIds" to defaultImportAlbumIds.toList(),
        )
    }

    fun state(): Map<String, Any> {
        return mapOf(
            "index" to index,
            "paused" to paused,
            "shuffle" to shuffle,
            "fit" to fit,
            "wallpaperScrolling" to wallpaperScrolling,
            "photoSource" to photoSource,
            "albums" to albums.map(WallpaperAlbum::asMap),
            "activeAlbumIds" to activeAlbumIds.toList(),
            "askAlbumsAfterImport" to askAlbumsAfterImport,
            "defaultImportAlbumIds" to defaultImportAlbumIds.toList(),
        )
    }

    // Builds preview data only for newly added wallpapers.
    fun wallpaperMaps(values: List<String>): List<Map<String, Any>> {
        val saved = wallpapers
        return values.mapNotNull { value ->
            val index = activeWallpapers.indexOf(value)
            if (value in saved) wallpaperMap(index.coerceAtLeast(0), value) else null
        }
    }

    fun wallpaperMapAt(index: Int): Map<String, Any>? =
        wallpaperAt(index)?.let { wallpaperMap(index, it) }

    // Writes the complete wallpaper collection and its settings into one portable file.
    fun writeBackup(output: java.io.OutputStream) {
        migrateExternalImages()
        val saved = wallpapers
        require(saved.size <= MAX_BACKUP_WALLPAPERS) {
            "This collection is too large to back up."
        }
        val manifestWallpapers = JSONArray()
        ZipOutputStream(output.buffered()).use { zip ->
            saved.forEachIndexed { index, value ->
                val source = localFile(value)
                    ?: throw IllegalStateException("A wallpaper could not be read.")
                require(source.length() <= MAX_BACKUP_IMAGE_BYTES) {
                    "A wallpaper is too large to back up."
                }
                val entryName = "images/$index.image"
                zip.putNextEntry(ZipEntry(entryName))
                source.inputStream().use { it.copyTo(zip) }
                zip.closeEntry()
                manifestWallpapers.put(
                    JSONObject()
                        .put("file", entryName)
                        .put("name", displayName(value))
                        .put("crop", JSONObject(crop(value).asMap()))
                        .put("albumIds", JSONArray(albumIds(value).toList())),
                )
            }
            val manifest = JSONObject()
                .put("format", BACKUP_FORMAT)
                .put("version", 3)
                .put("index", index)
                .put("paused", paused)
                .put("shuffle", shuffle)
                .put("fit", fit)
                .put("wallpaperScrolling", wallpaperScrolling)
                .put("photoSource", photoSource)
                .put("albums", JSONArray(albums.map { JSONObject(it.asMap()) }))
                .put("activeAlbumIds", JSONArray(activeAlbumIds.toList()))
                .put("askAlbumsAfterImport", askAlbumsAfterImport)
                .put("defaultImportAlbumIds", JSONArray(defaultImportAlbumIds.toList()))
                .put("wallpapers", manifestWallpapers)
            zip.putNextEntry(ZipEntry("manifest.json"))
            zip.write(manifest.toString().toByteArray())
            zip.closeEntry()
        }
    }

    // Validates a backup fully before replacing the current wallpaper collection.
    fun restoreBackup(input: InputStream) {
        val restoreRoot = File(appContext.cacheDir, "restore_${UUID.randomUUID()}").apply { mkdirs() }
        try {
            var manifestText: String? = null
            var extractedBytes = 0L
            ZipInputStream(input.buffered()).use { zip ->
                var entry = zip.nextEntry
                while (entry != null) {
                    if (!entry.isDirectory) {
                        if (entry.name == "manifest.json") {
                            manifestText = readLimited(zip, MAX_BACKUP_MANIFEST_BYTES)
                                .toString(Charsets.UTF_8)
                        } else if (entry.name.matches(Regex("images/\\d+\\.(jpg|image)"))) {
                            val destination = File(restoreRoot, entry.name.substringAfterLast('/'))
                            val copied = destination.outputStream().use {
                                copyLimited(zip, it, MAX_BACKUP_IMAGE_BYTES)
                            }
                            extractedBytes += copied
                            require(extractedBytes <= MAX_BACKUP_TOTAL_BYTES) {
                                "This backup is too large to restore."
                            }
                        }
                    }
                    zip.closeEntry()
                    entry = zip.nextEntry
                }
            }
            val manifest = JSONObject(manifestText ?: error("This is not a WakeWall backup."))
            require(manifest.optString("format") == BACKUP_FORMAT) { "This is not a WakeWall backup." }
            require(manifest.optInt("version") == 3) { "This backup version is not supported." }
            val restoredAlbums = manifest.getJSONArray("albums").let { values ->
                List(values.length()) { position ->
                    val item = values.getJSONObject(position)
                    WallpaperAlbum(item.getString("id"), item.getString("name"))
                }
            }
            val restoredAlbumIds = restoredAlbums.mapTo(mutableSetOf()) { it.id }
            val restoredActiveAlbums = manifest.getJSONArray("activeAlbumIds").let { values ->
                List(values.length()) { values.getString(it) }
                    .filterTo(linkedSetOf()) { it in restoredAlbumIds }
            }
            val restoredDefaultImportAlbums = manifest.getJSONArray("defaultImportAlbumIds").let { values ->
                List(values.length()) { values.getString(it) }
                    .filterTo(linkedSetOf()) { it in restoredAlbumIds }
            }
            val entries = manifest.getJSONArray("wallpapers")
            require(entries.length() <= MAX_BACKUP_WALLPAPERS) {
                "This backup contains too many wallpapers."
            }
            val restored = mutableListOf<RestoredWallpaper>()
            for (position in 0 until entries.length()) {
                val item = entries.getJSONObject(position)
                val source = File(restoreRoot, item.getString("file").substringAfterLast('/'))
                require(source.isFile && imageDimensions(source) != null) {
                    "A wallpaper in this backup is damaged."
                }
                val crop = item.optJSONObject("crop") ?: JSONObject()
                restored.add(
                    RestoredWallpaper(
                        source = source,
                        name = item.optString("name", "Photo"),
                        crop = CropTransform(
                            crop.optDouble("scale", 1.0).toFloat().coerceIn(1f, 4f),
                            crop.optDouble("offsetX", 0.0).toFloat().coerceIn(-4f, 4f),
                            crop.optDouble("offsetY", 0.0).toFloat().coerceIn(-4f, 4f),
                        ),
                        albumIds = item.getJSONArray("albumIds").let { ids ->
                            List(ids.length()) { ids.getString(it) }
                                .filterTo(linkedSetOf()) { it in restoredAlbumIds }
                        },
                    ),
                )
            }

            val wallpaperDirectory = File(appContext.filesDir, "wallpapers").apply { mkdirs() }
            val createdFiles = mutableListOf<File>()
            val newValues = try {
                restored.map { restoredWallpaper ->
                    val destination = File(wallpaperDirectory, "${UUID.randomUUID()}.image")
                    restoredWallpaper.source.copyTo(destination)
                    createdFiles.add(destination)
                    "$LOCAL_PREFIX${destination.name}"
                }
            } catch (error: Exception) {
                createdFiles.forEach(File::delete)
                throw error
            }
            val oldValues = wallpapers
            val editor = prefs.edit()
                .putString("wallpapers", JSONArray(newValues).toString())
                .putInt("index", manifest.optInt("index", 0).coerceAtLeast(0))
                .putBoolean("paused", manifest.optBoolean("paused", false))
                .putBoolean("shuffle", manifest.optBoolean("shuffle", true))
                .putString("fit", manifest.optString("fit", "cropToFill"))
                .putBoolean("wallpaper_scrolling", manifest.optBoolean("wallpaperScrolling", false))
                .putString("photo_source", manifest.optString("photoSource", "askEveryTime"))
                .putString("albums", JSONArray(restoredAlbums.map { JSONObject(it.asMap()) }).toString())
                .putString("active_album_ids", JSONArray(restoredActiveAlbums.toList()).toString())
                .putBoolean("ask_albums_after_import", manifest.optBoolean("askAlbumsAfterImport", true))
                .putString("default_import_album_ids", JSONArray(restoredDefaultImportAlbums.toList()).toString())
                .putInt("image_format_version", 1)
            oldValues.forEach { value ->
                editor
                    .remove(nameKey(value))
                    .remove(legacyNameKey(value))
                    .remove("${cropKey(value)}_scale")
                    .remove("${cropKey(value)}_x")
                    .remove("${cropKey(value)}_y")
                    .remove("${legacyCropKey(value)}_scale")
                    .remove("${legacyCropKey(value)}_x")
                    .remove("${legacyCropKey(value)}_y")
                    .remove(albumKey(value))
            }
            newValues.zip(restored).forEach { (value, restoredWallpaper) ->
                editor
                    .putString(nameKey(value), restoredWallpaper.name)
                    .putFloat("${cropKey(value)}_scale", restoredWallpaper.crop.scale)
                    .putFloat("${cropKey(value)}_x", restoredWallpaper.crop.offsetX)
                    .putFloat("${cropKey(value)}_y", restoredWallpaper.crop.offsetY)
                    .putString(albumKey(value), JSONArray(restoredWallpaper.albumIds.toList()).toString())
            }
            editor.apply()
            oldValues.forEach { value ->
                localFile(value)?.delete()
                deleteCachedPreviews(value)
            }
        } finally {
            restoreRoot.deleteRecursively()
        }
    }

    private fun saveWallpapers(wallpapers: List<String>) {
        prefs.edit().putString("wallpapers", JSONArray(wallpapers).toString()).apply()
        refreshActiveWallpapers()
    }

    private fun jsonArrayPreference(key: String): List<String> {
        val saved = prefs.getString(key, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(saved)
            List(array.length()) { array.getString(it) }
        }.getOrDefault(emptyList())
    }

    private fun saveAlbums(values: List<WallpaperAlbum>) {
        prefs.edit().putString(
            "albums",
            JSONArray(values.map { JSONObject(it.asMap()) }).toString(),
        ).apply()
    }

    private fun saveDefaultImportAlbumIds(ids: Set<String>) {
        val allowed = albums.mapTo(mutableSetOf()) { it.id }
        prefs.edit().putString(
            "default_import_album_ids",
            JSONArray(ids.filter { it in allowed }).toString(),
        ).apply()
    }

    private fun albumIds(value: String): Set<String> =
        jsonArrayPreference(albumKey(value)).toSet()

    private fun saveAlbumIds(value: String, ids: Set<String>) {
        prefs.edit().putString(albumKey(value), JSONArray(ids.toList()).toString()).apply()
        refreshActiveWallpapers()
    }

    // Moves older picker-based entries into the same reliable private storage.
    private fun migrateExternalImages() {
        var changed = false
        val imported = mutableListOf<String>()
        val migrated = wallpapers.mapNotNull { value ->
            if (value.startsWith(SAMPLE_PREFIX)) {
                changed = true
                null
            } else if (value.startsWith(LOCAL_PREFIX) && prefs.getInt("image_format_version", 0) < 1) {
                normalizeLocalImage(value)?.also { changed = true } ?: value
            } else if (value.startsWith(LOCAL_PREFIX)) {
                value
            } else {
                importIntoAppStorage(Uri.parse(value)).value?.also {
                    changed = true
                    imported.add(it)
                } ?: value
            }
        }
        if (changed) {
            saveWallpapers(migrated)
            imported.forEach(::commitImport)
        }
        prefs.edit().putInt("image_format_version", 1).apply()
    }

    private fun cropKey(index: Int): String =
        wallpaperAt(index)?.let(::cropKey) ?: "crop_index_$index"

    private fun cropKey(value: String): String = "crop_${storageKey(value)}"

    private fun legacyCropKey(index: Int): String =
        wallpaperAt(index)?.let(::legacyCropKey) ?: "crop_$index"

    private fun legacyCropKey(value: String): String = "crop_${value.hashCode()}"

    private fun nameKey(value: String): String = "name_${storageKey(value)}"
    private fun albumKey(value: String): String = "albums_${storageKey(value)}"

    private fun legacyNameKey(value: String): String = "name_${value.hashCode()}"

    private fun storageKey(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }

    private fun floatPreference(key: String, legacyKey: String, default: Float): Float =
        if (prefs.contains(key)) prefs.getFloat(key, default) else prefs.getFloat(legacyKey, default)

    private fun deleteMetadata(value: String) {
        prefs.edit()
            .remove(nameKey(value))
            .remove(legacyNameKey(value))
            .remove("${cropKey(value)}_scale")
            .remove("${cropKey(value)}_x")
            .remove("${cropKey(value)}_y")
            .remove("${legacyCropKey(value)}_scale")
            .remove("${legacyCropKey(value)}_x")
            .remove("${legacyCropKey(value)}_y")
            .remove(albumKey(value))
            .apply()
    }

    // Creates the small preview Flutter displays without passing the full photo.
    private fun wallpaperMap(index: Int, value: String): Map<String, Any> {
        val result = mutableMapOf<String, Any>(
            "crop" to crop(value).asMap(),
            "albumIds" to albumIds(value).toList(),
        )
        if (value.startsWith(SAMPLE_PREFIX)) {
            result["sampleIndex"] = value.removePrefix(SAMPLE_PREFIX).toIntOrNull() ?: 0
            return result
        }

        result["uri"] = value
        result["name"] = displayName(value)
        val sourcePreview = cachedSourcePreview(value)
        val displayDimensions = sourcePreview?.let(::imageDimensions) ?: imageDimensions(value)
        displayDimensions?.let { (width, height) ->
            result["imageWidth"] = width
            result["imageHeight"] = height
        }
        ensureWallpaperRenderFile(value, scrolling = false)
        if (wallpaperScrolling) ensureWallpaperRenderFile(value, scrolling = true)
        croppedPreview(value, MAIN_PREVIEW_WIDTH, 92, "main_crop_v2")?.let {
            result["mainPreview"] = it
        }
        croppedPreview(value, SMALL_PREVIEW_WIDTH, 84, "small_crop_v2")?.let {
            result["thumbnail"] = it
        }
        sourcePreview?.let { result["preview"] = it }
        return result
    }

    private fun displayName(value: String): String {
        if (value.startsWith(LOCAL_PREFIX)) {
            return prefs.getString(nameKey(value), null)
                ?: prefs.getString(legacyNameKey(value), "Photo")
                ?: "Photo"
        }
        val uri = Uri.parse(value)
        return runCatching {
            appContext.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
        }.getOrNull() ?: "Photo"
    }

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

    // Keeps a full-aspect source preview available for the crop editor.
    private fun cachedSourcePreview(value: String): ByteArray? {
        val directory = File(appContext.cacheDir, "wallpaper_previews").apply { mkdirs() }
        val file = File(directory, "${storageKey(value)}_source.jpg")
        if (file.exists()) return runCatching { file.readBytes() }.getOrNull()
        val bitmap = fullAspectPreview(value, SOURCE_PREVIEW_EDGE) ?: return null
        val saved = runCatching {
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 94, it) }
        }.getOrDefault(false)
        bitmap.recycle()
        return if (saved) runCatching { file.readBytes() }.getOrNull() else null
    }

    // Saves a screen-shaped crop snapshot so Flutter can display it immediately.
    private fun croppedPreview(
        value: String,
        targetWidth: Int,
        quality: Int,
        suffix: String,
    ): ByteArray? {
        val file = ensureCroppedPreviewFile(value, targetWidth, quality, suffix) ?: return null
        return runCatching { file.readBytes() }.getOrNull()
    }

    // Creates a finished phone-sized render so the live wallpaper can switch without decoding the original.
    private fun ensureWallpaperRenderFile(value: String, scrolling: Boolean): File? {
        val metrics = appContext.resources.displayMetrics
        val screenWidth = min(metrics.widthPixels, metrics.heightPixels).coerceAtLeast(1)
        val targetWidth = if (scrolling) {
            (screenWidth * SCROLLING_WIDTH_MULTIPLIER).roundToInt()
        } else {
            screenWidth
        }
        return ensureCroppedPreviewFile(
            value,
            targetWidth,
            100,
            if (scrolling) SCROLLING_RENDER_SUFFIX else WALLPAPER_RENDER_SUFFIX,
            targetHeight = if (scrolling) {
                max(metrics.widthPixels, metrics.heightPixels).coerceAtLeast(1)
            } else {
                null
            },
        )
    }

    fun wallpaperRenderFile(index: Int, scrolling: Boolean): File? {
        val value = wallpaperAt(index)?.takeUnless { it.startsWith(SAMPLE_PREFIX) } ?: return null
        val directory = File(appContext.cacheDir, "wallpaper_previews")
        val suffix = if (scrolling) SCROLLING_RENDER_SUFFIX else WALLPAPER_RENDER_SUFFIX
        val file = File(directory, "${storageKey(value)}_$suffix.jpg")
        return file.takeIf { it.isFile && it.length() > 0 }
            ?: ensureWallpaperRenderFile(value, scrolling)
    }

    // Builds wide renders before enabling scrolling so swipes never wait for image decoding.
    fun prepareScrollingRenders() {
        wallpapers.forEach { value ->
            if (!value.startsWith(SAMPLE_PREFIX)) ensureWallpaperRenderFile(value, scrolling = true)
        }
    }

    private fun ensureCroppedPreviewFile(
        value: String,
        targetWidth: Int,
        quality: Int,
        suffix: String,
        targetHeight: Int? = null,
    ): File? {
        val directory = File(appContext.cacheDir, "wallpaper_previews").apply { mkdirs() }
        val file = File(directory, "${storageKey(value)}_$suffix.jpg")
        if (file.exists()) return file

        val metrics = appContext.resources.displayMetrics
        val screenWidth = min(metrics.widthPixels, metrics.heightPixels).coerceAtLeast(1)
        val screenHeight = max(metrics.widthPixels, metrics.heightPixels).coerceAtLeast(1)
        val outputHeight = targetHeight
            ?: max(1, (targetWidth * screenHeight.toFloat() / screenWidth).roundToInt())
        val crop = crop(value)
        val source = fullAspectPreview(
            value,
            (max(targetWidth, outputHeight) * crop.scale.coerceIn(1f, 4f))
                .coerceAtMost(MAX_IMAGE_EDGE),
        ) ?: return null
        val snapshot = Bitmap.createBitmap(targetWidth, outputHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(snapshot)
        canvas.drawColor(Color.BLACK)

        val width = targetWidth.toFloat()
        val height = outputHeight.toFloat()
        val scale = max(width / source.width, height / source.height)
        val drawnWidth = source.width * scale
        val drawnHeight = source.height * scale
        val maxOffsetX = max(0f, (drawnWidth * crop.scale - width) / (2f * width))
        val maxOffsetY = max(0f, (drawnHeight * crop.scale - height) / (2f * height))
        canvas.save()
        canvas.translate(
            width / 2f + crop.offsetX.coerceIn(-maxOffsetX, maxOffsetX) * width,
            height / 2f + crop.offsetY.coerceIn(-maxOffsetY, maxOffsetY) * height,
        )
        canvas.scale(crop.scale, crop.scale)
        canvas.translate(-width / 2f, -height / 2f)
        canvas.drawBitmap(
            source,
            null,
            android.graphics.RectF(
                (width - drawnWidth) / 2f,
                (height - drawnHeight) / 2f,
                (width + drawnWidth) / 2f,
                (height + drawnHeight) / 2f,
            ),
            Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG),
        )
        canvas.restore()
        source.recycle()
        val saved = runCatching {
            file.outputStream().use { snapshot.compress(Bitmap.CompressFormat.JPEG, quality, it) }
        }.getOrDefault(false)
        snapshot.recycle()
        return file.takeIf { saved }
    }

    private fun deleteCachedPreviews(value: String) {
        fileStore.deleteCachedPreviews(value)
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

    // Reports the dimensions of the already-oriented preview shown by Flutter.
    private fun imageDimensions(bytes: ByteArray): Pair<Int, Int>? {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        return if (options.outWidth > 0 && options.outHeight > 0) {
            options.outWidth to options.outHeight
        } else {
            null
        }
    }

    // Keeps readable originals and only re-encodes unusual provider results as a fallback.
    private fun importIntoAppStorage(uri: Uri): ImportOutcome {
        val name = displayName(uri.toString())
        val originalDestination = File(importStagingDirectory(), "${UUID.randomUUID()}.image")
        val original = copyReadableOriginal(uri, originalDestination)
        if (original.saved) {
            val value = promoteImport(originalDestination, ".image") ?: return ImportOutcome()
            prefs.edit()
                .putString(nameKey(value), name)
                .putString("last_import_diagnostics", "$name: ${original.diagnostics}")
                .apply()
            return ImportOutcome(value = value)
        }

        originalDestination.delete()
        val fallbackDestination = File(importStagingDirectory(), "${UUID.randomUUID()}.jpg")
        val normalized = normalizeImage(uri, fallbackDestination)
        prefs.edit()
            .putString(
                "last_import_diagnostics",
                "$name: ${original.diagnostics}, ${normalized.diagnostics}",
            )
            .apply()
        if (!normalized.saved) {
            fallbackDestination.delete()
            return ImportOutcome(
                failure = normalized.fallbackBytes?.let { FailedImport(name, it, normalized.diagnostics) },
            )
        }
        val value = promoteImport(fallbackDestination, ".jpg") ?: return ImportOutcome()
        prefs.edit().putString(nameKey(value), name).apply()
        return ImportOutcome(value = value)
    }

    // Atomically moves a completed staged image into the real wallpaper collection.
    private fun promoteImport(staged: File, extension: String): String? {
        val directory = File(appContext.filesDir, "wallpapers").apply { mkdirs() }
        val destination = File(directory, "${UUID.randomUUID()}$extension")
        val value = "$LOCAL_PREFIX${destination.name}"
        recordPendingImport(value)
        if (staged.renameTo(destination)) return value
        cancelPendingImport(value)
        staged.delete()
        return null
    }

    // Copies the provider's original bytes when Android can fully decode them.
    private fun copyReadableOriginal(uri: Uri, destination: File): PreserveResult {
        val source = File.createTempFile(
            "wakewall_original_",
            ".image",
            importStagingDirectory(),
        )
        val diagnostics = mutableListOf<String>()
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
                if (source.length() > MAX_ORIGINAL_IMAGE_BYTES) {
                    diagnostics.add("$label:too_large")
                    return@forEach
                }
                if (validateOriginal(source) && runCatching {
                        source.copyTo(destination, overwrite = true)
                    }.isSuccess
                ) {
                    diagnostics.add("$label:preserved")
                    return PreserveResult(true, diagnostics.joinToString(", "))
                }
                diagnostics.add("$label:invalid")
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
                    if (source.length() > MAX_ORIGINAL_IMAGE_BYTES) {
                        diagnostics.add("$label:too_large")
                        return@forEach
                    }
                    if (validateOriginal(source) && runCatching {
                            source.copyTo(destination, overwrite = true)
                        }.isSuccess
                    ) {
                        diagnostics.add("$label:preserved")
                        return PreserveResult(true, diagnostics.joinToString(", "))
                    }
                    diagnostics.add("$label:invalid")
                }
            }
            PreserveResult(false, diagnostics.joinToString(", "))
        } finally {
            source.delete()
        }
    }

    // Fully decodes a bounded version before trusting copied provider bytes.
    private fun validateOriginal(source: File): Boolean {
        val dimensions = imageDimensions(source) ?: return false
        val decoded = decodeNormalizedBitmap(source, VALIDATION_IMAGE_EDGE) ?: return false
        val usable = isUsableBitmap(decoded, dimensions)
        decoded.recycle()
        return usable
    }

    // Tries every automatic provider access route before giving up on a selection.
    private fun normalizeImage(uri: Uri, destination: File): NormalizeResult {
        val source = File.createTempFile(
            "wakewall_import_",
            ".image",
            importStagingDirectory(),
        )
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
                if (source.length() <= MAX_FALLBACK_BYTES &&
                    source.length() > (fallbackBytes?.size ?: 0)
                ) {
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
                    if (source.length() <= MAX_FALLBACK_BYTES &&
                        source.length() > (fallbackBytes?.size ?: 0)
                    ) {
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
    private fun decodeNormalizedBitmap(
        source: File,
        maxEdge: Float = MAX_IMAGE_EDGE,
    ): Bitmap? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            runCatching {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(source)) { decoder, info, _ ->
                    val scale = (maxEdge / max(info.size.width, info.size.height).toFloat())
                        .coerceAtMost(1f)
                    decoder.setTargetSize(
                        max(1, (info.size.width * scale).roundToInt()),
                        max(1, (info.size.height * scale).roundToInt()),
                    )
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                }
            }.getOrNull()
        } else {
            decodeWithBitmapFactory(source, maxEdge)
        }
    }

    // Asks the photo provider for a complete rendered image instead of raw bytes.
    private fun loadProviderTransformedImage(uri: Uri, expectedSize: Pair<Int, Int>?): Bitmap? {
        return providerRenderSizes(expectedSize).firstNotNullOfOrNull { size ->
            val rendered = File.createTempFile(
                "wakewall_rendered_",
                ".image",
                importStagingDirectory(),
            )
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
    private fun decodeWithBitmapFactory(source: File, maxEdge: Float): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sampleSize = 1
        while (max(bounds.outWidth, bounds.outHeight) / sampleSize > maxEdge * 2) {
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
        val savedCrop = crop(value)
        val savedAlbums = albumIds(value)
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
        prefs.edit()
            .putString(nameKey(replacementValue), name)
            .putFloat("${cropKey(replacementValue)}_scale", savedCrop.scale)
            .putFloat("${cropKey(replacementValue)}_x", savedCrop.offsetX)
            .putFloat("${cropKey(replacementValue)}_y", savedCrop.offsetY)
            .putString(albumKey(replacementValue), JSONArray(savedAlbums.toList()).toString())
            .apply()
        deleteMetadata(value)
        deleteCachedPreviews(value)
        return replacementValue
    }

    private fun readLimited(input: InputStream, limit: Long): ByteArray {
        val output = ByteArrayOutputStream()
        copyLimited(input, output, limit)
        return output.toByteArray()
    }

    private fun copyLimited(input: InputStream, output: java.io.OutputStream, limit: Long): Long {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var copied = 0L
        while (true) {
            val count = input.read(buffer)
            if (count < 0) return copied
            copied += count
            require(copied <= limit) { "This backup contains a file that is too large." }
            output.write(buffer, 0, count)
        }
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
                flattened.compress(Bitmap.CompressFormat.JPEG, 98, it)
            }
        }.getOrDefault(false)
        flattened.recycle()
        return saved
    }

    fun localFile(value: String): File? {
        return fileStore.localFile(value)
    }

    fun openImage(value: String): InputStream? {
        return fileStore.openImage(value)
    }

    private fun importStagingDirectory(): File =
        fileStore.importStagingDirectory()

    companion object {
        private const val MAX_IMAGE_EDGE = 6144f
        private const val VALIDATION_IMAGE_EDGE = 2048f
        private const val SMALL_PREVIEW_WIDTH = 180
        private const val MAIN_PREVIEW_WIDTH = 720
        private const val SOURCE_PREVIEW_EDGE = 1920f
        private const val WALLPAPER_RENDER_SUFFIX = "wallpaper_crop_v1"
        private const val SCROLLING_RENDER_SUFFIX = "wallpaper_scroll_v1"
        const val SCROLLING_WIDTH_MULTIPLIER = 1.5f
        private const val SAMPLE_PREFIX = "sample:"
        private const val LOCAL_PREFIX = "local:"
        private const val BACKUP_FORMAT = "com.zambl.wakewall.backup"
        private const val MAX_BACKUP_WALLPAPERS = 1000
        private const val MAX_BACKUP_MANIFEST_BYTES = 1024L * 1024
        private const val MAX_BACKUP_IMAGE_BYTES = 256L * 1024 * 1024
        private const val MAX_BACKUP_TOTAL_BYTES = 2L * 1024 * 1024 * 1024
        private const val MAX_FALLBACK_BYTES = 64L * 1024 * 1024
        private const val MAX_ORIGINAL_IMAGE_BYTES = 256L * 1024 * 1024
        const val REMOVAL_UNDO_WINDOW_MS = 3_000L
    }
}

data class RestoredWallpaper(
    val source: File,
    val name: String,
    val crop: CropTransform,
    val albumIds: Set<String>,
)

data class WallpaperAlbum(val id: String, val name: String) {
    fun asMap(): Map<String, String> = mapOf("id" to id, "name" to name)
}

data class RemovedWallpaper(
    val value: String,
    val index: Int,
    val wasSelected: Boolean,
) {
    fun asMap(): Map<String, Any> = mapOf(
        "value" to value,
        "index" to index,
        "wasSelected" to wasSelected,
    )
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
    val importedValues: List<String>,
    val failed: Int,
    val failedImports: List<FailedImport>,
) {
    val imported: Int get() = importedValues.size
}

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

data class PreserveResult(
    val saved: Boolean,
    val diagnostics: String,
)
