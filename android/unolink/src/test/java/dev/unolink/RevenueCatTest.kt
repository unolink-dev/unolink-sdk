package dev.unolink

import dev.unolink.internal.Engine
import dev.unolink.internal.RevenueCatLink
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** connectRevenueCat reads RevenueCat's app user ID through a provider and reports it only when it changed. */
class RevenueCatLinkTest {
    @Test
    fun reports_the_id_once_then_only_changes() {
        val link = RevenueCatLink()
        var current: String? = "\$RCAnonymousID:abc"
        link.connect { current }
        assertEquals("\$RCAnonymousID:abc", link.changedId())
        assertNull(link.changedId())
        current = "account-42"
        assertEquals("account-42", link.changedId())
        assertNull(link.changedId())
    }

    @Test
    fun null_empty_too_long_or_a_throw_means_unknown_not_signed_out() {
        val link = RevenueCatLink()
        var current: () -> String? = { null }
        link.connect { current() }
        assertNull(link.changedId())
        current = { "  " }
        assertNull(link.changedId())
        current = { "x".repeat(Engine.MAX_USER_ID + 1) }
        assertNull(link.changedId())
        current = { throw UninitializedPropertyAccessException("Purchases isn't configured") }
        assertNull(link.changedId())
        current = { " account-42 " }
        assertEquals("account-42", link.changedId())
    }

    @Test
    fun disconnect_stops_reading_and_reconnect_reports_again() {
        val link = RevenueCatLink()
        link.connect { "a" }
        assertEquals("a", link.changedId())
        link.disconnect()
        assertFalse(link.isConnected)
        assertNull(link.changedId())
        link.connect { "a" }
        assertEquals("a", link.changedId())
    }
}

/** The public API over a test engine. */
class RevenueCatPublicApiTest {
    private lateinit var h: Harness

    @Before
    fun setUp() {
        h = Harness()
        h.engine.start(waitForReferrer = false)
        h.server.requests.clear()
    }

    @After
    fun tearDown() {
        Unolink.disconnectRevenueCat()
        Unolink.engine = null
    }

    private fun installUserIds() =
        h.server.requests.filter { it.path == "/v1/install" }.map { it.json.optString("userId").ifEmpty { null } }

    @Test
    fun connect_reports_revenuecats_id_and_a_change_goes_before_the_next_event() {
        Unolink.engine = h.engine
        var current = "\$RCAnonymousID:guest"
        Unolink.connectRevenueCat { current }
        assertEquals(listOf("\$RCAnonymousID:guest"), installUserIds())

        Unolink.signIn("apple") // same ID: not reported again
        assertEquals(listOf("\$RCAnonymousID:guest"), installUserIds())

        current = "account-42" // Purchases.logIn
        Unolink.paywallViewed("settings")
        Unolink.flush()
        assertEquals(listOf("\$RCAnonymousID:guest", "account-42"), installUserIds())
        assertEquals("account-42", h.server.requests.last { it.path == "/v1/events" }.json.getString("userId"))
    }

    @Test
    fun revenuecat_user_changed_reports_without_an_event() {
        Unolink.engine = h.engine
        var current = "\$RCAnonymousID:guest"
        Unolink.connectRevenueCat { current }
        current = "account-42"
        Unolink.revenueCatUserChanged()
        assertEquals(listOf("\$RCAnonymousID:guest", "account-42"), installUserIds())
        assertTrue(h.server.eventNames().isEmpty())
    }

    @Test
    fun connecting_before_configure_reports_once_configured() {
        Unolink.connectRevenueCat { "\$RCAnonymousID:guest" }
        Unolink.engine = h.engine
        Unolink.syncRevenueCat() // what configure and app-foreground do
        assertEquals(listOf("\$RCAnonymousID:guest"), installUserIds())
    }

    @Test
    fun unknown_id_leaves_the_user_id_alone() {
        Unolink.engine = h.engine
        Unolink.setUserId("account-42")
        Unolink.connectRevenueCat { null } // RevenueCat not configured yet
        Unolink.track("level_up")
        assertEquals(listOf("account-42"), installUserIds())
        assertEquals("account-42", h.store.getString(Engine.KEY_USER_ID))
    }

    @Test
    fun sign_up_skipped_sends_its_own_event() {
        Unolink.engine = h.engine
        Unolink.signUpSkipped(mapOf("screen" to "welcome"))
        Unolink.flush()
        val request = h.server.requests.last { it.path == "/v1/events" }
        Contract.assertValid("events-request", request.body!!)
        val events = request.json.getJSONArray("events")
        val event = events.getJSONObject(events.length() - 1)
        assertEquals("sign_up_skipped", event.getString("name"))
        assertEquals("welcome", event.getJSONObject("properties").getString("screen"))
    }

    @Test
    fun heard_from_sends_only_the_source() {
        Unolink.engine = h.engine
        Unolink.heardFrom("tiktok")
        Unolink.flush()
        val request = h.server.requests.last { it.path == "/v1/events" }
        Contract.assertValid("events-request", request.body!!)
        val events = request.json.getJSONArray("events")
        val event = events.getJSONObject(events.length() - 1)
        assertEquals("heard_from", event.getString("name"))
        val properties = event.getJSONObject("properties")
        assertEquals("tiktok", properties.getString("source"))
        assertEquals(1, properties.length())
        assertEquals(14, Unolink.HEARD_FROM_SOURCES.size)
    }
}
