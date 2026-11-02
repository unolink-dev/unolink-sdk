package dev.unolink

import dev.unolink.internal.Engine
import dev.unolink.internal.ReferrerDetails
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The deferred deep link is kept on the device until the app consumes it (or 30 days pass), so a new user who quits
 * mid-onboarding still gets it on the next launch. Listeners get it once per install, as before.
 */
class DeferredDeepLinkTest {
    private val referrer = "unolink_click_id=clk_01JA9Q3F6Z8W2K4N7R5T1V0X3Y&unolink_link=tiktok" +
        "&unolink_deep_link=%2Fpromo%2F3for2&unolink_p_offer=3for2"
    private val expected = UnolinkDeepLink("/promo/3for2", mapOf("offer" to "3for2"), "tiktok", "clk_01JA9Q3F6Z8W2K4N7R5T1V0X3Y")

    @After
    fun tearDown() {
        Unolink.engine = null
    }

    /** A first launch from a Unolink link. */
    private fun installedFromLink(): Harness = Harness().apply {
        engine.start(waitForReferrer = true)
        engine.onReferrer(ReferrerDetails(referrer))
    }

    @Test
    fun pending_link_survives_restarts_until_consumed() {
        val h = installedFromLink()
        assertEquals(expected, h.engine.pendingDeepLink)

        // The user quits mid-onboarding; the app comes back later.
        val second = h.relaunch()
        second.engine.start(waitForReferrer = false)
        assertEquals(expected, second.engine.pendingDeepLink)

        second.engine.consumeDeepLink()
        assertNull("gone at once", second.engine.pendingDeepLink)

        val third = second.relaunch()
        third.engine.start(waitForReferrer = false)
        assertNull("and on later launches", third.engine.pendingDeepLink)
    }

    @Test
    fun listener_gets_it_once_per_install_but_it_stays_pending_until_consumed() {
        val h = installedFromLink()
        val received = mutableListOf<UnolinkDeepLink>()
        h.engine.setListener { received += it }
        assertEquals(listOf(expected), received)

        val later = h.relaunch()
        later.engine.setListener { received += it }
        later.engine.start(waitForReferrer = false)
        assertEquals("an app that never consumes isn't sent it again", 1, received.size)
        assertEquals("but it's still pending", expected, later.engine.pendingDeepLink)
    }

    @Test
    fun a_link_no_listener_heard_goes_to_the_listener_of_a_later_launch() {
        val h = installedFromLink() // the app quit before setting its listener

        val later = h.relaunch()
        val received = mutableListOf<UnolinkDeepLink>()
        later.engine.setListener { received += it }
        later.engine.start(waitForReferrer = false)
        assertEquals(listOf(expected), received)
    }

    @Test
    fun a_consumed_link_isnt_delivered_to_a_later_listener() {
        val h = installedFromLink()
        h.engine.consumeDeepLink()

        val received = mutableListOf<UnolinkDeepLink>()
        h.engine.setListener { received += it }
        val later = h.relaunch()
        later.engine.setListener { received += it }
        later.engine.start(waitForReferrer = false)
        assertTrue(received.isEmpty())
    }

    @Test
    fun a_consumed_link_isnt_revived_when_the_install_is_registered_again() {
        val h = Harness()
        h.server.next(Contract.response("install-attributed"))
        h.engine.start(waitForReferrer = true)
        h.engine.onReferrer(ReferrerDetails("utm_source=tiktok"))
        assertEquals("/promo/3for2", h.engine.pendingDeepLink?.deepLink)
        h.engine.consumeDeepLink()

        // A new user ID re-sends /v1/install, whose answer carries the link again.
        h.server.next(Contract.response("install-attributed"))
        h.engine.setUserId("user-1")
        assertEquals("/v1/install", h.server.requests.last { it.path == "/v1/install" }.path)
        assertNull(h.engine.pendingDeepLink)
        val later = h.relaunch()
        later.engine.start(waitForReferrer = false)
        assertNull(later.engine.pendingDeepLink)
    }

    @Test
    fun the_first_link_wins_over_the_install_response() {
        val h = Harness()
        h.server.next(Contract.response("install-attributed"))
        h.engine.start(waitForReferrer = true)
        h.engine.onReferrer(ReferrerDetails(referrer.replace("%2Fpromo%2F3for2", "%2Ffirst")))
        assertEquals("/first", h.engine.pendingDeepLink?.deepLink)
    }

    @Test
    fun an_unconsumed_link_expires_after_30_days() {
        val h = installedFromLink()
        h.clock.time += Engine.DEEP_LINK_TTL_MS - 1
        assertEquals(expected, h.engine.pendingDeepLink)
        h.clock.time += 1
        assertNull(h.engine.pendingDeepLink)

        val later = h.relaunch()
        val received = mutableListOf<UnolinkDeepLink>()
        later.engine.setListener { received += it }
        later.engine.start(waitForReferrer = false)
        assertNull(later.engine.pendingDeepLink)
        assertTrue("an expired link isn't delivered either", received.isEmpty())
        assertEquals("and is forgotten", null, later.store.getString(Engine.KEY_DEEP_LINK))
    }

    @Test
    fun consuming_before_any_link_is_known_does_nothing() {
        val h = Harness()
        h.engine.start(waitForReferrer = true)
        h.engine.consumeDeepLink()
        h.engine.onReferrer(ReferrerDetails(referrer))
        assertEquals(expected, h.engine.pendingDeepLink)
    }

    @Test
    fun installs_that_got_their_link_from_an_older_sdk_have_nothing_pending() {
        val store = MemoryStore()
        store.putString(Engine.KEY_INSTALL_ID, "11111111-1111-4111-8111-111111111111")
        store.putBoolean(Engine.KEY_REGISTERED, true)
        store.putBoolean(Engine.KEY_DEEP_LINK_DONE, true) // 0.3.2 delivered it and kept nothing else
        val h = Harness(store = store)
        h.engine.start(waitForReferrer = false)
        h.server.next(Contract.response("install-attributed"))
        h.engine.setUserId("user-1") // re-registers; the answer carries the link
        assertNull(h.engine.pendingDeepLink)
    }

    @Test
    fun a_damaged_stored_link_is_ignored() {
        val store = MemoryStore()
        store.putString(Engine.KEY_DEEP_LINK, "{not json")
        val h = Harness(store = store)
        h.engine.start(waitForReferrer = false)
        assertNull(h.engine.pendingDeepLink)
    }

    @Test
    fun public_api_reads_and_consumes_through_the_engine() {
        assertNull("before configure", Unolink.getPendingDeferredDeepLink())
        Unolink.consumeDeferredDeepLink() // no engine: does nothing, doesn't throw

        val h = installedFromLink()
        Unolink.engine = h.engine
        assertEquals(expected, Unolink.getPendingDeferredDeepLink())
        Unolink.consumeDeferredDeepLink()
        assertNull(Unolink.getPendingDeferredDeepLink())
    }
}
