package com.zambl.wakewall

import android.content.Context
import android.os.Build
import android.os.UserManager
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

    fun credentialStorageAvailable(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
            appContext.getSystemService(UserManager::class.java)?.isUserUnlocked != false

    fun frameFile(): File? =
        target.takeIf { it.isFile && it.length() > 0 }

    fun saveFrom(source: File?): Boolean {
        if (source?.isFile != true || source.length() <= 0) {
            clear()
            return false
        }
        val sourcePath = source.absolutePath
        val sourceLength = source.length()
        val sourceModified = source.lastModified()
        if (
            target.isFile &&
            target.length() > 0 &&
            prefs.getString("source_path", null) == sourcePath &&
            prefs.getLong("source_length", -1) == sourceLength &&
            prefs.getLong("source_modified", -1) == sourceModified
        ) {
            return true
        }

        val temp = File(directory, "current.tmp")
        val saved = runCatching {
            source.copyTo(temp, overwrite = true)
            if (!temp.renameTo(target)) temp.copyTo(target, overwrite = true)
            temp.delete()
            true
        }.getOrDefault(false)
        if (!saved) {
            temp.delete()
            return false
        }
        prefs.edit()
            .putString("source_path", sourcePath)
            .putLong("source_length", sourceLength)
            .putLong("source_modified", sourceModified)
            .apply()
        return true
    }

    fun clear() {
        File(directory, "current.tmp").delete()
        target.delete()
        prefs.edit().clear().apply()
    }
}
