package dev.unolink

/** Reads RevenueCat's current app user ID for [Unolink.connectRevenueCat]. Return null while it isn't known. */
public fun interface AppUserIdProvider {
    public fun appUserId(): String?
}
