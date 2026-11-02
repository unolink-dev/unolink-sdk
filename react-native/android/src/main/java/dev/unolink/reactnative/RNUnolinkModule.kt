package dev.unolink.reactnative

import android.util.Log
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap
import dev.unolink.LogLevel
import dev.unolink.Unolink
import dev.unolink.UnolinkDeepLink
import dev.unolink.UnolinkOptions
import java.math.BigDecimal

/** React Native bridge to the Unolink Android SDK. */
class RNUnolinkModule(private val context: ReactApplicationContext) : NativeRNUnolinkSpec(context) {

    override fun getName(): String = NAME

    override fun configure(apiKey: String, baseUrl: String?, logLevel: String, debug: Boolean, sdkVersion: String) {
        val level = when (logLevel) {
            "none" -> LogLevel.NONE
            "error" -> LogLevel.ERROR
            "info" -> LogLevel.INFO
            "debug" -> LogLevel.DEBUG
            else -> LogLevel.WARN
        }
        val options = UnolinkOptions(baseUrl = baseUrl?.ifEmpty { null } ?: UnolinkOptions.DEFAULT_BASE_URL, logLevel = level, debug = debug)
        Unolink.configureFromWrapper(context.applicationContext, apiKey, options, "react-native", sdkVersion)
        Unolink.setDeferredDeepLinkListener { link -> emitOnDeferredDeepLink(link.toMap()) }
    }

    /** Kept on disk by the Android SDK until consumed, so it survives app restarts. */
    override fun getPendingDeferredDeepLink(): WritableMap? = Unolink.getPendingDeferredDeepLink()?.toMap()

    override fun consumeDeferredDeepLink() = Unolink.consumeDeferredDeepLink()

    override fun track(name: String, properties: ReadableMap?) {
        Unolink.track(name, properties?.toHashMap())
    }

    override fun purchase(amount: String, currency: String, productId: String?, properties: ReadableMap?) {
        val value = amount.toBigDecimalOrNull()
        if (value == null) {
            Log.e("Unolink", "purchase(): amount \"$amount\" is not a number. Not recorded.")
            return
        }
        Unolink.purchase(value, currency, productId, properties?.toHashMap())
    }

    override fun setUserId(userId: String?) = Unolink.setUserId(userId)

    override fun flush() = Unolink.flush()

    override fun setEnabled(enabled: Boolean) = Unolink.setEnabled(enabled)

    override fun getInstallId(): String? = Unolink.getInstallId()

    companion object {
        const val NAME = "RNUnolink"
    }
}

private fun UnolinkDeepLink.toMap(): WritableMap = Arguments.createMap().apply {
    if (deepLink != null) putString("deepLink", deepLink) else putNull("deepLink")
    putMap("params", Arguments.createMap().apply { params.forEach { (k, v) -> putString(k, v) } })
    if (linkSlug != null) putString("linkSlug", linkSlug) else putNull("linkSlug")
    putString("clickId", clickId)
}

private fun String.toBigDecimalOrNull(): BigDecimal? = try { BigDecimal(this) } catch (e: NumberFormatException) { null }
