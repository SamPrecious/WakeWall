package com.zambl.wakewall

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

// Persists unfinished imports and deletions so process death cannot leak files.
class WakeWallTransactionStore(private val prefs: SharedPreferences) {
    // Removal entries survive app death until either Undo wins or the timer expires.
    fun recordRemoval(value: String, deadline: Long) = synchronized(LOCK) {
        saveRemovals(pendingRemovals().apply { put(value, deadline) })
    }

    fun cancelRemoval(value: String) = synchronized(LOCK) {
        val pending = pendingRemovals()
        if (pending.remove(value) != null) saveRemovals(pending)
    }

    fun pendingRemovals(): MutableMap<String, Long> = synchronized(LOCK) {
        val saved = prefs.getString(PENDING_REMOVALS_KEY, null) ?: return@synchronized mutableMapOf()
        runCatching {
            val json = JSONObject(saved)
            json.keys().asSequence().associateWithTo(mutableMapOf()) { json.getLong(it) }
        }.getOrDefault(mutableMapOf())
    }

    fun saveRemovals(pending: Map<String, Long>) = synchronized(LOCK) {
        val editor = prefs.edit()
        if (pending.isEmpty()) editor.remove(PENDING_REMOVALS_KEY)
        else editor.putString(PENDING_REMOVALS_KEY, JSONObject(pending).toString())
        editor.commit()
    }

    fun recordImport(value: String) = synchronized(LOCK) {
        saveImports(pendingImports().apply { add(value) })
    }

    // A finished import is now safely present in the wallpaper list.
    fun finishImport(value: String) = synchronized(LOCK) {
        val pending = pendingImports()
        if (pending.remove(value)) saveImports(pending)
    }

    fun pendingImports(): MutableSet<String> = synchronized(LOCK) {
        val saved = prefs.getString(PENDING_IMPORTS_KEY, null) ?: return@synchronized mutableSetOf()
        runCatching {
            val json = JSONArray(saved)
            List(json.length()) { json.getString(it) }.toMutableSet()
        }.getOrDefault(mutableSetOf())
    }

    fun clearImports() = synchronized(LOCK) {
        prefs.edit().remove(PENDING_IMPORTS_KEY).commit()
    }

    fun <T> locked(action: () -> T): T = synchronized(LOCK, action)

    private fun saveImports(pending: Set<String>) {
        val editor = prefs.edit()
        if (pending.isEmpty()) editor.remove(PENDING_IMPORTS_KEY)
        else editor.putString(PENDING_IMPORTS_KEY, JSONArray(pending.toList()).toString())
        editor.commit()
    }

    companion object {
        private const val PENDING_REMOVALS_KEY = "pending_removals"
        private const val PENDING_IMPORTS_KEY = "pending_imports"
        private val LOCK = Any()
    }
}
