package dev.unolink

import dev.unolink.internal.Engine
import dev.unolink.internal.HttpResponse
import dev.unolink.internal.ReferrerDetails
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EngineTest {
    private val referrer = "unolink_click_id=clk_01JA9Q3F6Z8W2K4N7R5T1V0X3Y&unolink_link=tiktok&utm_source=tiktok" +
        "&unolink_deep_link=%2Fpromo%2F3for2&unolink_p_offer=3for2"

    @Test
    fun first_launch_waits_for_the_referrer_registers_then_sends_events() {
        val h = Harness()
        h.engine.start(waitForReferrer = true)
        assertTrue("nothing is sent before the referrer is known", h.server.requests.isEmpty())

        h.engine.onReferrer(ReferrerDetails(referrer, 1760000000, 1760000100))

        assertEquals(listOf("/v1/install", "/v1/events"), h.server.paths())
        val install = h.server.requests[0]
        Contract.assertValid("install-request", install.body!!)
        assertEquals(referrer, install.json.getJSONObject("playReferrer").getString("raw"))
        assertEquals(1760000100, install.json.getJSONObject("playReferrer").getLong("installBeginAt"))
        Contract.assertValid("events-request", h.server.requests[1].body!!)
        assertEquals(listOf("first_open", "session_start"), h.server.eventNames())
        assertTrue(h.queue.lines.isEmpty())
    }

    @Test
    fun registers_without_a_referrer_when_play_doesnt_answer_in_time() {
        val h = Harness()
        h.engine.start(waitForReferrer = true)
        h.scheduler.advance(Engine.REFERRER_TIMEOUT_MS)

        assertEquals("/v1/install", h.server.paths().first())
        assertTrue(!h.server.requests[0].json.has("playReferrer"))
    }

    @Test
    fun deferred_deep_link_comes_from_the_referrer_once_even_with_a_late_listener() {
        val h = Harness()
        h.engine.start(waitForReferrer = true)
        h.engine.onReferrer(ReferrerDetails(referrer))

        val received = mutableListOf<UnolinkDeepLink>()
        h.engine.setListener { received += it }
        h.engine.setListener { received += it }

        assertEquals(1, received.size)
        assertEquals(UnolinkDeepLink("/promo/3for2", mapOf("offer" to "3for2"), "tiktok", "clk_01JA9Q3F6Z8W2K4N7R5T1V0X3Y"), received[0])

        val later = h.relaunch()
        later.engine.setListener { received += it }
        later.engine.start(waitForReferrer = false)
        assertEquals("never delivered twice", 1, received.size)
    }

    @Test
    fun deep_link_falls_back_to_the_install_response() {
        val h = Harness()
        h.server.next(Contract.response("install-attributed"))
        val received = mutableListOf<UnolinkDeepLink>()
        h.engine.setListener { received += it }
        h.engine.start(waitForReferrer = true)
        h.engine.onReferrer(ReferrerDetails("utm_source=tiktok")) // no Unolink values inline

        assertEquals("/promo/3for2", received.single().deepLink)
        assertEquals("tiktok", received.single().linkSlug)
    }

    @Test
    fun ios_style_start_without_referrer_and_unattributed_install_delivers_no_deep_link() {
        val h = Harness()
        val received = mutableListOf<UnolinkDeepLink>()
        h.engine.setListener { received += it }
        h.engine.start(waitForReferrer = false)
        assertTrue(received.isEmpty())
        assertEquals("/v1/install", h.server.paths().first())
    }

    @Test
    fun events_wait_for_registration_and_survive_restarts_while_offline() {
        val h = Harness()
        h.server.networkError()
        h.engine.start(waitForReferrer = false)
        h.engine.track("level_up", mapOf("level" to 3), null)
        assertEquals(listOf("/v1/install"), h.server.paths())
        assertEquals(3, h.queue.lines.size) // first_open, session_start, level_up

        val later = h.relaunch()
        later.engine.start(waitForReferrer = false)
        assertEquals(listOf("first_open", "session_start", "level_up", "session_start"), later.server.eventNames())
    }

    @Test
    fun network_errors_back_off_and_retry() {
        val h = Harness()
        h.engine.start(waitForReferrer = false)
        h.server.requests.clear()
        h.server.networkError()
        h.server.networkError()
        h.engine.track("a", null, null)
        h.engine.flushNow()
        assertEquals(1, h.server.requests.size)

        h.scheduler.advance(750) // first retry: 1 s x (0.5 + 0.5/2)
        assertEquals(2, h.server.requests.size)
        h.scheduler.advance(1_500) // second: 2 s x 0.75
        assertEquals(3, h.server.requests.size)
        assertTrue(h.queue.lines.isEmpty())
    }

    @Test
    fun install_required_registers_again_and_resends_the_batch() {
        val h = Harness()
        h.engine.start(waitForReferrer = false)
        h.server.requests.clear()
        h.server.next(Contract.response("problem-install-required"))
        h.engine.track("paywall_viewed", null, null)
        h.engine.flushNow()

        assertEquals(listOf("/v1/events", "/v1/install", "/v1/events"), h.server.paths())
        assertEquals(h.server.requests[0].body, h.server.requests[2].body)
        assertTrue(h.queue.lines.isEmpty())
    }

    @Test
    fun invalid_key_stops_sending_until_the_next_launch_but_keeps_events() {
        val h = Harness()
        h.server.next(Contract.response("problem-invalid-key"))
        h.engine.start(waitForReferrer = false)
        h.engine.track("a", null, null)
        h.engine.flushNow()

        assertEquals(1, h.server.requests.size)
        assertEquals(3, h.queue.lines.size)
        assertTrue(h.log.errors.any { it.contains("Invalid SDK key") })
    }

    @Test
    fun sdk_disabled_stops_and_keeps_nothing() {
        val h = Harness()
        h.server.next(Contract.response("problem-sdk-disabled"))
        h.engine.start(waitForReferrer = false)
        h.engine.track("a", null, null)

        assertEquals(1, h.server.requests.size)
        assertTrue(h.queue.lines.isEmpty())
    }

    @Test
    fun validation_errors_drop_the_batch_and_rejected_events_are_not_retried() {
        val h = Harness()
        h.engine.start(waitForReferrer = false)
        h.server.next(Contract.response("problem-validation"))
        h.engine.track("a", null, null)
        h.engine.flushNow()
        assertTrue(h.queue.lines.isEmpty())

        h.server.next(Contract.response("events-some-rejected"))
        h.engine.track("b", null, null)
        h.engine.flushNow()
        assertTrue(h.queue.lines.isEmpty())
    }

    @Test
    fun purchase_carries_an_exact_decimal_amount_and_matches_the_schema() {
        val h = Harness()
        h.engine.start(waitForReferrer = false)
        h.server.requests.clear()
        h.engine.track("purchase", mapOf("product_id" to "pro_yearly", "trial" to false, "price" to 49.99), "49.99" to "usd")
        h.engine.flushNow()

        val body = h.server.requests.single().body!!
        Contract.assertValid("events-request", body)
        val revenue = h.server.requests.single().json.getJSONArray("events").getJSONObject(0).getJSONObject("revenue")
        assertEquals("49.99", revenue.getString("amount"))
        assertEquals("USD", revenue.getString("currency"))
    }

    @Test
    fun invalid_names_are_refused_locally() {
        val h = Harness()
        h.engine.start(waitForReferrer = false)
        h.server.requests.clear()
        h.engine.track("bad name", null, null)
        h.engine.flushNow()
        assertTrue(h.server.requests.isEmpty())
        assertTrue(h.log.errors.single().contains("invalid"))
    }

    @Test
    fun batches_hold_at_most_100_events_and_flush_automatically_at_20() {
        val h = Harness()
        h.server.networkError() // keep everything queued at first
        h.engine.start(waitForReferrer = false)
        repeat(248) { h.engine.track("e$it", null, null) } // + first_open, session_start = 250
        val again = h.relaunch()
        again.engine.start(waitForReferrer = false)

        val sizes = again.server.requests.filter { it.path == "/v1/events" }.map { it.json.getJSONArray("events").length() }
        assertEquals(listOf(100, 100, 51), sizes) // 250 + this launch's session_start
    }

    @Test
    fun queue_is_capped_dropping_the_oldest() {
        val h = Harness()
        h.server.networkError()
        h.engine.start(waitForReferrer = false)
        repeat(Engine.MAX_QUEUE + 50) { h.engine.track("e$it", null, null) }
        assertEquals(Engine.MAX_QUEUE, h.queue.lines.size)
        assertTrue(h.queue.lines.last().contains("\"e${Engine.MAX_QUEUE + 49}\""))
    }

    @Test
    fun opting_out_deletes_the_queue_and_sends_nothing_across_launches() {
        val h = Harness()
        h.server.networkError()
        h.engine.start(waitForReferrer = false)
        h.engine.setEnabled(false)
        h.engine.track("a", null, null)
        assertTrue(h.queue.lines.isEmpty())

        val later = h.relaunch()
        later.server.requests.clear()
        later.engine.start(waitForReferrer = false)
        later.engine.track("b", null, null)
        later.engine.flushNow()
        assertTrue(later.server.requests.isEmpty())
    }

    @Test
    fun a_new_session_starts_after_30_minutes_in_the_background() {
        val h = Harness()
        h.engine.start(waitForReferrer = false)
        h.engine.onForeground()
        h.engine.onBackground()
        h.clock.time += 5 * 60_000
        h.engine.onForeground()
        h.engine.onBackground()
        h.clock.time += 31 * 60_000
        h.engine.onForeground()
        h.engine.flushNow()

        assertEquals(listOf("first_open", "session_start", "app_background", "app_background", "session_start"), h.server.eventNames())
    }

    @Test
    fun install_id_is_random_stable_and_not_resent_after_registration() {
        val h = Harness()
        h.engine.start(waitForReferrer = false)
        val id = h.engine.publicInstallId!!
        assertTrue(Regex("^[0-9a-f-]{36}$").matches(id))

        val later = h.relaunch()
        later.server.requests.clear()
        later.engine.start(waitForReferrer = false)
        assertEquals(id, later.engine.publicInstallId)
        assertTrue("/v1/install" !in later.server.paths())
        assertNull(later.server.requests.firstOrNull { it.path == "/v1/install" })
    }

    @Test
    fun server_errors_are_retried_not_dropped() {
        val h = Harness()
        h.engine.start(waitForReferrer = false)
        h.server.next(Contract.response("server-error"), HttpResponse(429, null))
        h.engine.track("a", null, null)
        h.engine.flushNow()
        assertTrue(h.queue.lines.isNotEmpty())
        h.scheduler.advance(10_000)
        assertTrue(h.queue.lines.isEmpty())
    }
}
