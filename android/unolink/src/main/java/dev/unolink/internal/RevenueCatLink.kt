package dev.unolink.internal

import dev.unolink.AppUserIdProvider

/**
 * Keeps the user ID in step with RevenueCat's app user ID without depending on RevenueCat: the app hands over a
 * provider that reads it, and the SDK asks it at configure, when the app comes to the foreground and before each event.
 * Only a changed ID is reported. Null, empty or a thrown exception (RevenueCat not configured yet) mean "not known
 * right now", never "signed out": after logOut RevenueCat itself moves to a new anonymous ID, reported like any other.
 */
internal class RevenueCatLink {
    @Volatile private var provider: AppUserIdProvider? = null
    private var reported: String? = null

    val isConnected: Boolean get() = provider != null

    @Synchronized
    fun connect(appUserId: AppUserIdProvider) {
        provider = appUserId
        reported = null
    }

    @Synchronized
    fun disconnect() {
        provider = null
        reported = null
    }

    /** The ID to report now: RevenueCat's current one if it changed since the last report, otherwise null. */
    fun changedId(): String? {
        val read = provider ?: return null
        // Read outside the lock: the provider calls into RevenueCat.
        val id = runCatching { read.appUserId() }.getOrNull()?.trim()
        if (id.isNullOrEmpty() || id.length > Engine.MAX_USER_ID) return null
        synchronized(this) {
            if (provider == null || id == reported) return null
            reported = id
            return id
        }
    }
}
