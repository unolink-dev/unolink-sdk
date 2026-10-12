package dev.unolink.internal

import dev.unolink.DeferredDeepLinkListener
import dev.unolink.UnolinkDeepLink
import org.json.JSONObject
import java.io.IOException
import java.util.UUID

/**
 * Everything the SDK does, without Android: install registration, the event queue, batching, retries and the
 * deferred deep link. Runs only on [scheduler]'s single thread; public entry points hop onto it.
 *
 * Rules (contract/README.md): /v1/install is sent first and retried until it succeeds; events wait for it. Batches of
 * up to 100 are removed from the queue once the server answers 202 (accepted, duplicate or rejected alike). 409 means
 * "register the install again". 401/403 stop sending until the next launch. Network errors, 408, 429 and 5xx back
 * off exponentially (1 s to 5 min, with jitter).
 */
internal class Engine(
    private val device: DeviceInfo,
    private val transport: Transport,
    private val store: KeyValueStore,
    private val queueStore: QueueStore,
    private val scheduler: Scheduler,
    private val clock: Clock,
    private val log: Logger,
    private val runOnMain: (() -> Unit) -> Unit,
    private val random: () -> Double = Math::random,
) {
    companion object {
        const val MAX_QUEUE = 1000
        const val BATCH_SIZE = 100
        const val FLUSH_AT = 20
        const val FLUSH_INTERVAL_MS = 15_000L
        const val REFERRER_TIMEOUT_MS = 10_000L
        const val SESSION_GAP_MS = 30 * 60_000L
        const val MIN_BACKOFF_MS = 1_000L
        const val MAX_BACKOFF_MS = 5 * 60_000L

        const val KEY_INSTALL_ID = "install_id"
        const val KEY_REGISTERED = "install_registered"
        const val KEY_OPTED_OUT = "opted_out"
        const val KEY_DEEP_LINK_DONE = "deep_link_done"
        const val KEY_USER_ID = "user_id"
        const val MAX_USER_ID = 256
    }

    private val queue = ArrayDeque<String>()
    private var installId: String? = null
    private var registered = false
    private var stopped = false            // 401/403: until the next launch
    private var sdkDisabled = false        // 403: the plan has no SDK, so nothing is even queued until the next launch
    private var optedOut = false
    private var inFlight = false
    private var backoffMs = 0L
    private var reRegistrations = 0        // 409s in a row; guards against a loop if the server keeps answering 409
    private var retryScheduled = false
    private var referrer: ReferrerDetails? = null
    private var referrerSettled = false    // read, unavailable, or timed out
    private var foreground = false
    private var timerRunning = false
    private var backgroundAt = 0L
    private var pendingDeepLink: UnolinkDeepLink? = null
    @Volatile private var listener: DeferredDeepLinkListener? = null
    @Volatile var publicInstallId: String? = null
        private set

    /** Cold start. [waitForReferrer]: Android first launch, where Google Play may know which link this came from. */
    fun start(waitForReferrer: Boolean) = scheduler.execute {
        optedOut = store.getBoolean(KEY_OPTED_OUT)
        queue.addAll(queueStore.load().takeLast(MAX_QUEUE))
        registered = store.getBoolean(KEY_REGISTERED)
        installId = store.getString(KEY_INSTALL_ID)
        if (installId == null) {
            installId = UUID.randomUUID().toString()
            store.putString(KEY_INSTALL_ID, installId)
            registered = false
            enqueue("first_open", null, null)
        }
        publicInstallId = installId
        if (optedOut) {
            log.info("Tracking is off for this install (setEnabled(false)).")
            return@execute
        }
        enqueue("session_start", null, null)

        if (registered || !waitForReferrer) {
            referrerSettled = true
            if (!registered) register() else flush()
        } else {
            scheduler.schedule(REFERRER_TIMEOUT_MS) {
                if (!referrerSettled) {
                    log.info("Install referrer not available in time; registering without it.")
                    settleReferrer(null)
                }
            }
        }
    }

    /** Google Play answered (or couldn't): register the install, and deliver the deep link carried by the referrer. */
    fun onReferrer(details: ReferrerDetails?) = scheduler.execute { if (!referrerSettled) settleReferrer(details) }

    private fun settleReferrer(details: ReferrerDetails?) {
        referrerSettled = true
        referrer = details
        details?.deepLink()?.let(::offerDeepLink)
        register()
    }

    fun setListener(l: DeferredDeepLinkListener?) {
        listener = l
        scheduler.execute { pendingDeepLink?.let { deliver(it) } }
    }

    fun track(name: String, properties: Map<String, Any?>?, revenue: Pair<String, String>?) = scheduler.execute {
        if (optedOut) return@execute
        if (!Payloads.isValidName(name)) {
            log.error("Event name \"$name\" is invalid: start with a letter; letters, digits, _ and . only; at most 64.")
            return@execute
        }
        enqueue(name, Payloads.properties(properties, log), revenue)
        if (queue.size >= FLUSH_AT) flush()
    }

    fun flushNow() = scheduler.execute { flush() }

    /** The app's own user ID (e.g. RevenueCat app user ID). Unolink stores only a keyed hash of it. Null clears it. */
    fun setUserId(userId: String?) = scheduler.execute {
        val clean = userId?.trim()?.takeIf { it.isNotEmpty() }
        if (clean != null && clean.length > MAX_USER_ID) {
            log.error("setUserId(): at most $MAX_USER_ID characters; ignored.")
            return@execute
        }
        store.putString(KEY_USER_ID, clean)
    }

    fun setEnabled(enabled: Boolean) = scheduler.execute {
        optedOut = !enabled
        store.putBoolean(KEY_OPTED_OUT, optedOut)
        if (optedOut) {
            queue.clear()
            persist()
            log.info("Tracking turned off: queued events deleted, nothing more will be sent.")
        } else {
            log.info("Tracking turned on.")
            if (!registered) register() else flush()
        }
    }

    fun onForeground() = scheduler.execute {
        foreground = true
        val now = clock.now()
        if (backgroundAt > 0 && now - backgroundAt >= SESSION_GAP_MS && !optedOut) enqueue("session_start", null, null)
        backgroundAt = 0
        if (!timerRunning) {
            timerRunning = true
            scheduler.schedule(FLUSH_INTERVAL_MS, ::tick)
        }
    }

    fun onBackground() = scheduler.execute {
        foreground = false
        backgroundAt = clock.now()
        if (!optedOut) enqueue("app_background", null, null)
        flush()
    }

    private fun tick() {
        if (!foreground) {
            timerRunning = false
            return
        }
        flush()
        scheduler.schedule(FLUSH_INTERVAL_MS, ::tick)
    }

    private fun enqueue(name: String, properties: JSONObject?, revenue: Pair<String, String>?) {
        if (sdkDisabled) return
        queue.addLast(Payloads.event(UUID.randomUUID().toString(), name, clock.now(), properties, revenue).toString())
        while (queue.size > MAX_QUEUE) {
            queue.removeFirst()
            log.warn("Event queue is full ($MAX_QUEUE); dropped the oldest event.")
        }
        persist()
    }

    private fun persist() = queueStore.save(queue.toList())

    private fun register() {
        val id = installId ?: return
        if (stopped || optedOut || inFlight || registered || !referrerSettled) return
        inFlight = true
        val response = call("POST", "/v1/install", Payloads.install(id, device, referrer, store.getString(KEY_USER_ID)))
        inFlight = false
        when {
            response == null -> scheduleRetry()
            response.status in 200..299 -> {
                registered = true
                store.putBoolean(KEY_REGISTERED, true)
                backoffMs = 0
                Payloads.deepLinkFromInstall(response.body)?.let(::offerDeepLink)
                flush()
            }
            else -> handleFailure(response, batchSize = 0)
        }
    }

    private fun flush() {
        if (stopped || optedOut || inFlight || retryScheduled) return
        if (!registered) {
            register()
            return
        }
        if (queue.isEmpty()) return
        val batch = queue.take(BATCH_SIZE)
        inFlight = true
        val response = call("POST", "/v1/events", Payloads.events(installId!!, batch, store.getString(KEY_USER_ID)))
        inFlight = false
        when {
            response == null -> scheduleRetry()
            response.status in 200..299 -> {
                repeat(batch.size) { queue.removeFirst() }
                persist()
                backoffMs = 0
                reRegistrations = 0
                logRejected(response.body)
                if (queue.isNotEmpty()) flush()
            }
            else -> handleFailure(response, batch.size)
        }
    }

    private fun handleFailure(response: HttpResponse, batchSize: Int) {
        val code = Payloads.problemCode(response.body)
        when {
            response.status == 409 && code == "install_required" && reRegistrations >= 2 -> scheduleRetry()
            response.status == 409 && code == "install_required" -> {
                reRegistrations++
                log.info("Server doesn't know this install yet; registering it again.")
                registered = false
                store.putBoolean(KEY_REGISTERED, false)
                register()
            }
            response.status == 401 -> {
                stopped = true
                log.error("Invalid SDK key (401). Check the key in Unolink → your app → SDK. Nothing is sent until the next launch.")
            }
            response.status == 403 -> {
                stopped = true
                sdkDisabled = true
                queue.clear()
                persist()
                log.error("The SDK isn't included in this app's Unolink plan (403 ${code ?: ""}). Events are not recorded.")
            }
            response.status == 408 || response.status == 429 || response.status >= 500 -> scheduleRetry()
            else -> {
                // 400 and other client errors never succeed on retry: drop what was sent.
                log.error("Unolink rejected a request (${response.status} ${code ?: ""}); dropped it.")
                if (batchSize > 0) {
                    repeat(minOf(batchSize, queue.size)) { queue.removeFirst() }
                    persist()
                } else {
                    stopped = true // a malformed install request won't fix itself
                }
            }
        }
    }

    private fun scheduleRetry() {
        if (retryScheduled) return
        backoffMs = if (backoffMs == 0L) MIN_BACKOFF_MS else minOf(backoffMs * 2, MAX_BACKOFF_MS)
        val delay = (backoffMs * (0.5 + random() / 2)).toLong()
        retryScheduled = true
        log.debug("Retrying in ${delay} ms.")
        scheduler.schedule(delay) {
            retryScheduled = false
            if (!registered) register() else flush()
        }
    }

    private fun call(method: String, path: String, body: String): HttpResponse? = try {
        transport.send(method, path, body)
    } catch (e: IOException) {
        log.debug("Network error on $path: ${e.message}")
        null
    }

    private fun logRejected(body: String?) {
        val rejected = runCatching { JSONObject(body ?: return).optJSONArray("rejected") }.getOrNull() ?: return
        for (i in 0 until rejected.length()) {
            val r = rejected.optJSONObject(i) ?: continue
            log.warn("Event rejected (${r.optString("code")}): ${r.optString("message")}")
        }
    }

    private fun offerDeepLink(link: UnolinkDeepLink) {
        if (store.getBoolean(KEY_DEEP_LINK_DONE) || pendingDeepLink != null) return
        pendingDeepLink = link
        deliver(link)
    }

    private fun deliver(link: UnolinkDeepLink) {
        val l = listener ?: return
        if (store.getBoolean(KEY_DEEP_LINK_DONE)) return
        store.putBoolean(KEY_DEEP_LINK_DONE, true)
        pendingDeepLink = null
        runOnMain { l.onDeferredDeepLink(link) }
    }
}
