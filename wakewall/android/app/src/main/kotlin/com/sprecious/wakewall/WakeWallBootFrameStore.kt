package com.sprecious.wakewall

import android.content.Context
import android.os.Build
import android.os.UserManager
import android.system.Os
import java.io.File

// Keeps one already-rendered frame available before Android unlocks normal app storage.
class WakeWallBootFrameStore(context: Context) {
    private val appContext = context.applicationContext
    private val storageContext =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            appContext.createDeviceProtectedStorageContext()
        } else {
            appContext
        }
    private val prefs = storageContext.getSharedPreferences("wakewall_boot", Context.MODE_PRIVATE)
    private val directory = File(storageContext.filesDir, "boot_frame").apply { mkdirs() }
    private val target = File(directory, "current.jpg")

    // Normal app storage is unavailable until first unlock on Direct Boot devices.
    fun credentialStorageAvailable(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
            appContext.getSystemService(UserManager::class.java)?.isUserUnlocked != false

    fun frameFile(): File? =
        target.takeIf { it.isFile && it.length() > 0 }

    fun saveFrom(source: File?): Boolean = synchronized(LOCK) {
        if (source?.isFile != true || source.length() <= 0) {
            clear()
            return@synchronized false
        }
        val sourcePath = source.absolutePath
        val sourceLength = source.length()
        val sourceModified = source.lastModified()
        // Avoid rewriting the boot copy when the rendered wallpaper has not changed.
        if (
            target.isFile &&
            target.length() > 0 &&
            prefs.getString("source_path", null) == sourcePath &&
            prefs.getLong("source_length", -1) == sourceLength &&
            prefs.getLong("source_modified", -1) == sourceModified
        ) {
            return@synchronized true
        }

        val temp = File(directory, "current.tmp")
        val saved = runCatching {
            source.copyTo(temp, overwrite = true)
            check(temp.length() == sourceLength)
            // POSIX rename replaces the old frame atomically on Android's local filesystem.
            Os.rename(temp.absolutePath, target.absolutePath)
            target.isFile && target.length() == sourceLength
        }.getOrDefault(false)
        temp.delete()
        if (!saved) {
            return@synchronized false
        }
        prefs.edit()
            .putString("source_path", sourcePath)
            .putLong("source_length", sourceLength)
            .putLong("source_modified", sourceModified)
            .apply()
        true
    }

    fun clear() = synchronized(LOCK) {
        File(directory, "current.tmp").delete()
        target.delete()
        prefs.edit().clear().apply()
    }

    companion object {
        private val LOCK = Any()
    }
}
