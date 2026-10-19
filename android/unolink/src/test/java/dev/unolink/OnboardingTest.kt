package dev.unolink

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

/** onboardingStep / onboardingSkipped send only step, index and flow, in a batch the contract accepts. */
class OnboardingTest {
    private fun send(name: String, properties: Map<String, Any?>): JSONObject {
        val h = Harness()
        h.engine.start(waitForReferrer = false)
        h.server.requests.clear()
        h.engine.track(name, properties, null)
        h.engine.flushNow()
        val body = h.server.requests.last().body!!
        Contract.assertValid("events-request", body)
        val event = h.server.requests.last().json.getJSONArray("events").getJSONObject(0)
        assertEquals(name, event.getString("name"))
        return event.getJSONObject("properties")
    }

    private fun JSONObject.keySet() = keys().asSequence().toSet()

    @Test
    fun step_carries_step_index_and_flow() {
        val properties = send("onboarding_step", Unolink.onboarding("goal", 1, "v2"))
        assertEquals(setOf("step", "index", "flow"), properties.keySet())
        assertEquals("goal", properties.getString("step"))
        assertEquals(1, properties.getInt("index"))
        assertEquals("v2", properties.getString("flow"))
    }

    @Test
    fun missing_index_and_flow_are_left_out() {
        val properties = send("onboarding_step", Unolink.onboarding("goal", null, null))
        assertEquals(setOf("step"), properties.keySet())
    }

    @Test
    fun skipped_has_the_same_shape() {
        val properties = send("onboarding_skipped", Unolink.onboarding("notifications", 3, null))
        assertEquals(setOf("step", "index"), properties.keySet())
        assertEquals("notifications", properties.getString("step"))
    }
}
