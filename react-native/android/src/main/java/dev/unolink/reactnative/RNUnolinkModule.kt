package dev.unolink.reactnative

import android.util.Log
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap
import dev.unolink.LogLevel
import dev.unolink.Unolink
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
        Unolink.setDeferredDeepLinkListener { link ->
            val params = Arguments.createMap().apply { link.params.forEach { (k, v) -> putString(k, v) } }
            emitOnDeferredDeepLink(Arguments.createMap().apply {
                if (link.deepLink != null) putString("deepLink", link.deepLink) else putNull("deepLink")
                putMap("params", params)
                if (link.linkSlug != null) putString("linkSlug", link.linkSlug) else putNull("linkSlug")
                putString("clickId", link.clickId)
            })
        }
    }

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

private fun String.toBigDecimalOrNull(): BigDecimal? = try { BigDecimal(this) } catch (e: NumberFormatException) { null }
