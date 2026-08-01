package com.sprecious.wakewall

import android.content.Context
import android.net.Uri
import java.io.File
import java.io.InputStream

// Owns WakeWall's private files and removes anything no longer referenced.
class WakeWallFileStore(
    context: Context,
    private val activeWallpapers: () -> List<String>,
    private val pendingRemovals: () -> Set<String>,
    private val pendingImports: () -> Set<String>,
    private val clearPendingImports: () -> Unit,
    private val storageKey: (String) -> String,
    private val deleteMetadata: (String) -> Unit,
) {
    private val appContext = context.applicationContext

    fun localFile(value: String): File? {
        if (!value.startsWith(LOCAL_PREFIX)) return null
        return File(wallpaperDirectory(), value.removePrefix(LOCAL_PREFIX))
    }

    fun openImage(value: String): InputStream? =
        localFile(value)?.inputStream()
            ?: appContext.contentResolver.openInputStream(Uri.parse(value))

    fun importStagingDirectory(): File =
        File(appContext.filesDir, IMPORT_STAGING_DIRECTORY).apply { mkdirs() }

    fun deleteRemovalFiles(value: String) {
        localFile(value)?.delete()
        deleteCachedPreviews(value)
        deleteMetadata(value)
    }

    fun deleteCachedPreviews(value: String) {
        val directory = previewDirectory()
        // Delete both stable-key and older hash-key previews from previous builds.
        PREVIEW_SUFFIXES.forEach {
            File(directory, "${storageKey(value)}_$it.jpg").delete()
            File(directory, "${value.hashCode()}_$it.jpg").delete()
        }
    }

    fun cleanupOrphanedFiles() {
        // Keep active wallpapers and pending Undo removals; everything else is abandoned.
        val retained = (activeWallpapers() + pendingRemovals()).toSet()
        val retainedLocalNames = retained.mapNotNull { localFile(it)?.name }.toSet()
        wallpaperDirectory().listFiles()?.forEach { file ->
            if (file.isFile && file.name !in retainedLocalNames) file.delete()
        }

        val retainedPreviewNames = retained.flatMap { value ->
            CURRENT_PREVIEW_SUFFIXES.map { suffix ->
                "${storageKey(value)}_$suffix.jpg"
            }
        }.toSet()
        previewDirectory().listFiles()?.forEach { file ->
            if (file.isFile && file.name !in retainedPreviewNames) {
                file.delete()
            }
        }
    }

    fun cleanupIncompleteImports() {
        // If an import died before entering the list, remove its private file and staging data.
        val active = activeWallpapers().toSet()
        pendingImports().forEach { value ->
            if (value !in active) deleteRemovalFiles(value)
        }
        clearPendingImports()
        importStagingDirectory().deleteRecursively()
    }

    fun cleanStorage(cleanupExpiredRemovals: () -> Unit): Long {
        // Return reclaimed bytes so the UI can report that cleanup actually did work.
        val before = managedStorageBytes()
        cleanupExpiredRemovals()
        cleanupIncompleteImports()
        cleanupOrphanedFiles()
        appContext.cacheDir.listFiles()
            ?.filter { it.isDirectory && it.name.startsWith("restore_") }
            ?.forEach(File::deleteRecursively)
        return (before - managedStorageBytes()).coerceAtLeast(0)
    }

    private fun managedStorageBytes(): Long {
        val managed = sequenceOf(
            wallpaperDirectory(),
            importStagingDirectory(),
            previewDirectory(),
        ) + appContext.cacheDir.listFiles()
            .orEmpty()
            .asSequence()
            .filter { it.isDirectory && it.name.startsWith("restore_") }
        return managed.sumOf(::directoryBytes)
    }

    private fun directoryBytes(file: File): Long =
        if (file.isFile) file.length() else file.listFiles()?.sumOf(::directoryBytes) ?: 0

    private fun wallpaperDirectory(): File =
        File(appContext.filesDir, "wallpapers").apply { mkdirs() }

    private fun previewDirectory(): File =
        File(appContext.cacheDir, "wallpaper_previews")

    companion object {
        const val IMPORT_STAGING_DIRECTORY = "wallpaper_imports"
        private const val LOCAL_PREFIX = "local:"
        private val CURRENT_PREVIEW_SUFFIXES = listOf(
            "source",
            "small_crop_v2",
            "main_crop_v3",
            "wallpaper_crop_v1",
            "wallpaper_scroll_v3",
        )
        private val PREVIEW_SUFFIXES = CURRENT_PREVIEW_SUFFIXES + listOf(
            "small",
            "main",
            "large",
            "main_crop_v2",
            "wallpaper_scroll_v1",
            "wallpaper_scroll_v2",
        )
    }
}
