package dev.unolink

import android.content.Context
import android.util.Log
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import dev.unolink.internal.AndroidDevice
import dev.unolink.internal.Engine
import dev.unolink.internal.ExecutorScheduler
import dev.unolink.internal.FileKeyValueStore
import dev.unolink.internal.FileQueueStore
import dev.unolink.internal.HttpTransport
import dev.unolink.internal.LogcatLogger
import dev.unolink.internal.Payloads
import dev.unolink.internal.PlayInstallReferrer
import dev.unolink.internal.ReferrerDetails
import dev.unolink.internal.SystemClock
import dev.unolink.internal.mainHandler
import java.math.BigDecimal

/**
 * Unolink: which link or ad brings installs, onboarding, paywall views, trials and purchases.
 *
 * Call [configure] once, in `Application.onCreate`. Everything else is safe to call from any thread, never blocks,
 * and never throws: events are queued on disk and sent in the background.
 *
 * ```kotlin
 * Unolink.configure(this, "ulk_…")
 * Unolink.paywallViewed()
 * Unolink.purchase(BigDecimal("49.99"), "USD", productId = "pro_yearly")
 * ```
 */
public object Unolink {
    /** This SDK's version. */
    public const val VERSION: String = "0.1.1"

    @Volatile private var engine: Engine? = null
    @Volatile private var pendingListener: DeferredDeepLinkListener? = null

    /**
     * Starts the SDK: registers the install on first launch (with Google Play's install referrer, so installs from
     * your Unolink links are attributed), then reports sessions and your events.
     *
     * @param apiKey The app's SDK key from Unolink (dashboard → your app → Settings → API keys). It is fine to ship it in the app.
     */
    @JvmStatic
    @JvmOverloads
    public fun configure(context: Context, apiKey: String, options: UnolinkOptions = UnolinkOptions()) {
        configure(context, apiKey, options, sdkName = "android", sdkVersion = VERSION)
    }

    /** For the React Native and Flutter packages, which report their own name and version. */
    @JvmStatic
    public fun configureFromWrapper(context: Context, apiKey: String, options: UnolinkOptions, sdkName: String, sdkVersion: String) {
        configure(context, apiKey, options, sdkName, sdkVersion)
    }

    private fun configure(context: Context, apiKey: String, options: UnolinkOptions, sdkName: String, sdkVersion: String) {
        synchronized(this) {
            if (engine != null) {
                Log.w("Unolink", "configure() was already called; ignoring the second call.")
                return
            }
            val app = context.applicationContext
            val log = LogcatLogger(options.logLevel)
            if (!apiKey.startsWith("ulk_")) log.error("That doesn't look like an SDK key (they start with \"ulk_\").")

            val dir = app.noBackupFilesDir
            val store = FileKeyValueStore(dir)
            val firstLaunch = store.getString(Engine.KEY_INSTALL_ID) == null
            val created = Engine(
                device = AndroidDevice.info(app, sdkName, sdkVersion, options.debug),
                transport = HttpTransport(options.baseUrl, apiKey, "Unolink-Android/$VERSION"),
                store = store,
                queueStore = FileQueueStore(dir),
                scheduler = ExecutorScheduler(),
                clock = SystemClock,
                log = log,
                runOnMain = { block -> mainHandler.post(block) },
            )
            engine = created
            pendingListener?.let(created::setListener)

            // The referrer only matters until the install is registered; it's read on the first launch.
            val needsReferrer = firstLaunch || !store.getBoolean(Engine.KEY_REGISTERED)
            created.start(waitForReferrer = needsReferrer)
            if (needsReferrer) {
                val simulated = options.debugInstallReferrer?.takeIf { AndroidDevice.isDebuggable(app) }
                if (simulated != null) {
                    log.warn("Using the simulated install referrer from UnolinkOptions (debug build only).")
                    created.onReferrer(ReferrerDetails(simulated))
                } else {
                    PlayInstallReferrer.read(app, log, created::onReferrer)
                }
            }

            mainHandler.post {
                ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
                    override fun onStart(owner: LifecycleOwner) = created.onForeground()
                    override fun onStop(owner: LifecycleOwner) = created.onBackground()
                })
            }
        }
    }

    /** Your own event, e.g. `track("level_up", mapOf("level" to 3))`. Values: strings, numbers or booleans. */
    @JvmStatic
    @JvmOverloads
    public fun track(name: String, properties: Map<String, Any?>? = null) {
        withEngine { it.track(name, properties, null) }
    }

    /** The user finished the onboarding screens (send it before any paywall or sign-up that follows them). */
    @JvmStatic
    @JvmOverloads
    public fun onboardingCompleted(properties: Map<String, Any?>? = null) {
        withEngine { it.track("onboarding_completed", properties, null) }
    }

    /**
     * An onboarding screen appeared. Call it when the screen shows (`LaunchedEffect`), not from its button. [step] is a
     * fixed screen ID such as "goal", never user data; [index] its position (0, 1, 2…); [flow] which onboarding, if you
     * run more than one. Free: an onboarding costs one event (its [onboardingCompleted]) however many screens it has.
     */
    @JvmStatic
    @JvmOverloads
    public fun onboardingStep(step: String, index: Int? = null, flow: String? = null) {
        withEngine { it.track("onboarding_step", onboarding(step, index, flow), null) }
    }

    /** The user tapped Skip on the onboarding screen [step]. Free, like [onboardingStep]. */
    @JvmStatic
    @JvmOverloads
    public fun onboardingSkipped(step: String, index: Int? = null, flow: String? = null) {
        withEngine { it.track("onboarding_skipped", onboarding(step, index, flow), null) }
    }

    /**
     * A paywall was shown. [placement] says where, so the funnel can tell them apart: "onboarding", "feature_gate", or
     * your own name.
     */
    @JvmStatic
    @JvmOverloads
    public fun paywallViewed(placement: String? = null, properties: Map<String, Any?>? = null) {
        withEngine { it.track("paywall_viewed", withValue("placement", placement, properties), null) }
    }

    /** The user closed a paywall without buying. */
    @JvmStatic
    @JvmOverloads
    public fun paywallSkipped(placement: String? = null, properties: Map<String, Any?>? = null) {
        withEngine { it.track("paywall_skipped", withValue("placement", placement, properties), null) }
    }

    /** An account was created (in many apps this comes after the paywall). */
    @JvmStatic
    @JvmOverloads
    public fun signUp(method: String? = null, properties: Map<String, Any?>? = null) {
        withEngine { it.track("sign_up", withValue("method", method, properties), null) }
    }

    /** The user closed the store's purchase sheet without paying. */
    @JvmStatic
    @JvmOverloads
    public fun purchaseCancelled(productId: String? = null, properties: Map<String, Any?>? = null) {
        withEngine { it.track("purchase_cancelled", withProduct(productId, properties), null) }
    }

    /** The purchase failed (payment declined, store error). [reason] is your own short description. */
    @JvmStatic
    @JvmOverloads
    public fun purchaseFailed(productId: String? = null, reason: String? = null, properties: Map<String, Any?>? = null) {
        withEngine { it.track("purchase_failed", withValue("reason", reason, withProduct(productId, properties)), null) }
    }

    /**
     * Your app's own ID for the signed-in (or anonymous) user, e.g. the RevenueCat app user ID. It lets Unolink join
     * server-side purchase data (renewals, cancellations, refunds) to the link the install came from. Unolink stores only
     * a keyed hash of it, never the ID itself. Pass null on sign-out.
     */
    @JvmStatic
    public fun setUserId(userId: String?) {
        withEngine { it.setUserId(userId) }
    }

    /** A free trial started. */
    @JvmStatic
    @JvmOverloads
    public fun trialStarted(productId: String? = null, properties: Map<String, Any?>? = null) {
        withEngine { it.track("trial_started", withProduct(productId, properties), null) }
    }

    /**
     * A purchase, with its price. Pass the amount as a [BigDecimal] (e.g. from Play Billing's micros / 1,000,000) so it
     * is never rounded, and the ISO 4217 currency, e.g. "USD".
     */
    @JvmStatic
    @JvmOverloads
    public fun purchase(amount: BigDecimal, currency: String, productId: String? = null, properties: Map<String, Any?>? = null) {
        withEngine { engine ->
            val value = Payloads.amount(amount)
            when {
                value == null -> Log.e("Unolink", "purchase(): amount must be zero or more, with at most 6 decimals. Not recorded.")
                !Payloads.isValidCurrency(currency) -> Log.e("Unolink", "purchase(): currency must be a 3-letter ISO 4217 code such as \"USD\". Not recorded.")
                else -> engine.track("purchase", withProduct(productId, properties), value to currency)
            }
        }
    }

    /**
     * Called once per install, on the main thread, when the install came from a Unolink link: open
     * [UnolinkDeepLink.deepLink]. Android only. If the link is known before you set the listener, it's delivered when
     * you set it.
     */
    @JvmStatic
    public fun setDeferredDeepLinkListener(listener: DeferredDeepLinkListener?) {
        pendingListener = listener
        engine?.setListener(listener)
    }

    /** The random ID of this install (null before [configure]). It identifies no person or device. */
    @JvmStatic
    public fun getInstallId(): String? = engine?.publicInstallId

    /** Sends queued events now, e.g. before a known app exit. Normally not needed. */
    @JvmStatic
    public fun flush() {
        withEngine { it.flushNow() }
    }

    /** Turns tracking off (queued events are deleted) or back on. Remembered across launches. */
    @JvmStatic
    public fun setEnabled(enabled: Boolean) {
        withEngine { it.setEnabled(enabled) }
    }

    private fun withProduct(productId: String?, properties: Map<String, Any?>?): Map<String, Any?>? =
        withValue("product_id", productId, properties)

    /** The server accepts only these three on onboarding events. */
    private fun onboarding(step: String, index: Int?, flow: String?): Map<String, Any?> =
        buildMap {
            put("step", step)
            if (index != null) put("index", index)
            if (flow != null) put("flow", flow)
        }

    private fun withValue(key: String, value: String?, properties: Map<String, Any?>?): Map<String, Any?>? =
        if (value == null) properties else (properties.orEmpty() + (key to value))

    private inline fun withEngine(block: (Engine) -> Unit) {
        val e = engine
        if (e == null) Log.w("Unolink", "Call Unolink.configure(...) in Application.onCreate first; event ignored.")
        else block(e)
    }
}
