package dev.unolink.flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import dev.unolink.LogLevel
import dev.unolink.Unolink
import dev.unolink.UnolinkOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.math.BigDecimal

/** Flutter bridge to the Unolink Android SDK. */
class UnolinkFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dev.unolink/sdk")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> {
                val level = when (call.argument<String>("logLevel")) {
                    "none" -> LogLevel.NONE
                    "error" -> LogLevel.ERROR
                    "info" -> LogLevel.INFO
                    "debug" -> LogLevel.DEBUG
                    else -> LogLevel.WARN
                }
                val baseUrl = call.argument<String>("baseUrl")?.ifEmpty { null } ?: UnolinkOptions.DEFAULT_BASE_URL
                Unolink.configureFromWrapper(
                    context, call.argument<String>("apiKey") ?: "",
                    UnolinkOptions(baseUrl = baseUrl, logLevel = level, debug = call.argument<Boolean>("debug") ?: false),
                    "flutter", call.argument<String>("sdkVersion") ?: "0",
                )
                Unolink.setDeferredDeepLinkListener { link ->
                    main.post {
                        channel.invokeMethod("onDeferredDeepLink", mapOf(
                            "deepLink" to link.deepLink,
                            "params" to link.params,
                            "linkSlug" to link.linkSlug,
                            "clickId" to link.clickId,
                        ))
                    }
                }
            }
            "track" -> Unolink.track(call.argument<String>("name") ?: "", call.argument<Map<String, Any?>>("properties"))
            "purchase" -> {
                val amount = call.argument<String>("amount")?.let { runCatching { BigDecimal(it) }.getOrNull() }
                if (amount == null) {
                    Log.e("Unolink", "purchase(): amount is not a number. Not recorded.")
                } else {
                    Unolink.purchase(amount, call.argument<String>("currency") ?: "", call.argument<String>("productId"),
                        call.argument<Map<String, Any?>>("properties"))
                }
            }
            "setUserId" -> Unolink.setUserId(call.argument<String>("userId"))
            "flush" -> Unolink.flush()
            "setEnabled" -> Unolink.setEnabled(call.argument<Boolean>("enabled") ?: true)
            "getInstallId" -> {
                result.success(Unolink.getInstallId())
                return
            }
            else -> {
                result.notImplemented()
                return
            }
        }
        result.success(null)
    }
}
