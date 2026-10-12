package dev.unolink.sample

import android.app.Application
import dev.unolink.LogLevel
import dev.unolink.Unolink
import dev.unolink.UnolinkDeepLink
import dev.unolink.UnolinkOptions

class SampleApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Unolink.configure(
            this,
            BuildConfig.UNOLINK_KEY,
            UnolinkOptions(
                baseUrl = BuildConfig.UNOLINK_BASE_URL,
                logLevel = LogLevel.DEBUG,
                debugInstallReferrer = BuildConfig.SIMULATE_REFERRER.ifEmpty { null },
            ),
        )
        // A real app would navigate here; the sample shows it on screen.
        Unolink.setDeferredDeepLinkListener { link -> lastDeepLink = link }
    }

    companion object {
        @Volatile var lastDeepLink: UnolinkDeepLink? = null
    }
}
