package dev.unolink

/**
 * Where the app should take someone who just installed it from a Unolink link (Android only: Google Play's install
 * referrer carries it; iPhones offer no reliable equivalent without fingerprinting).
 *
 * @property deepLink The link's deep link as set in the dashboard, e.g. "/promo/3for2" or "myapp://promo", or null.
 * @property params The link's parameters.
 * @property linkSlug The campaign link's path (e.g. "tiktok"), or null for the app's main link.
 * @property clickId The click that led to the install.
 */
public data class UnolinkDeepLink(
    public val deepLink: String?,
    public val params: Map<String, String>,
    public val linkSlug: String?,
    public val clickId: String,
)

/** Receives the deferred deep link once per install, on the main thread. */
public fun interface DeferredDeepLinkListener {
    public fun onDeferredDeepLink(link: UnolinkDeepLink)
}
