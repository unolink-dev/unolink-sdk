package dev.unolink

/**
 * Optional settings for [Unolink.configure].
 *
 * @property baseUrl The SDK API. Defaults to production; use `https://api-uat.unolink.dev` while testing.
 * @property logLevel How much the SDK logs (tag "Unolink").
 * @property debug Marks this install as a test device, so the dashboard leaves it out unless "Include test devices"
 *   is on. `null` (default) means: true for debuggable builds.
 * @property debugInstallReferrer Debug builds only: pretend Google Play returned this install referrer, e.g.
 *   `unolink_click_id=clk_…&unolink_deep_link=%2Fpromo`. Lets you test deferred deep links without a Play install.
 *   Ignored in release builds.
 */
public class UnolinkOptions @JvmOverloads constructor(
    public val baseUrl: String = DEFAULT_BASE_URL,
    public val logLevel: LogLevel = LogLevel.WARN,
    public val debug: Boolean? = null,
    public val debugInstallReferrer: String? = null,
) {
    public companion object {
        public const val DEFAULT_BASE_URL: String = "https://api.unolink.dev"
    }
}
