package com.example.clawix.android.bridge

import android.content.Context
import android.content.SharedPreferences

/**
 * Persists the set of chat ids the user has NOT yet seen since their
 * last assistant turn finished. Mirrors iOS `UnreadChatsCache`. Lives
 * in plain SharedPreferences (no secrets) so cold-start can paint the
 * dot before the WebSocket lands.
 */
interface UnreadChatTracker {
    fun load(): Set<String>
    fun save(ids: Set<String>)
    fun mark(id: String)
    fun clear(id: String)
    fun clearAll()
}

class UnreadChatsCache(context: Context) : UnreadChatTracker {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("clawix_unread_v1", Context.MODE_PRIVATE)

    override fun load(): Set<String> = prefs.getStringSet(KEY, emptySet()) ?: emptySet()

    override fun save(ids: Set<String>) {
        prefs.edit().putStringSet(KEY, ids.toList().takeLast(maxEntries).toSet()).apply()
    }

    override fun mark(id: String) {
        save(load() + id)
    }

    override fun clear(id: String) {
        save(load() - id)
    }

    override fun clearAll() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val KEY = "ids"
        private const val maxEntries = 200
    }
}
