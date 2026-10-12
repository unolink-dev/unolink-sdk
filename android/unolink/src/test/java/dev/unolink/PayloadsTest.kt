package dev.unolink

import dev.unolink.internal.Payloads
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.math.BigDecimal

class PayloadsTest {
    @Test
    fun amounts_are_exact_decimal_strings() {
        assertEquals("49.99", Payloads.amount(BigDecimal("49.990")))
        assertEquals("100", Payloads.amount(BigDecimal("1E+2")))
        assertEquals("0.000001", Payloads.amount(BigDecimal("0.000001")))
        assertNull(Payloads.amount(BigDecimal("0.0000001")))
        assertNull(Payloads.amount(BigDecimal("-1")))
    }

    @Test
    fun timestamps_are_utc_iso_8601_with_millis() {
        assertEquals("2025-10-09T08:53:20.000Z", Payloads.timestamp(1_760_000_000_000))
    }

    @Test
    fun properties_keep_only_flat_values() {
        val p = Payloads.properties(mapOf("s" to "x".repeat(300), "n" to 3, "b" to true, "list" to listOf(1), "nan" to Double.NaN), QuietLogger())!!
        assertEquals(setOf("s", "n", "b"), p.keys().asSequence().toSet())
        assertEquals(200, p.getString("s").length)
    }
}
