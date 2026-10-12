package dev.unolink.internal

import dev.unolink.UnolinkDeepLink
import org.json.JSONObject
import java.math.BigDecimal
import java.net.URLDecoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Builds request bodies and reads responses exactly as contract/schemas describe them. */
internal object Payloads {
    private val NAME = Regex("^[A-Za-z][A-Za-z0-9_.]{0,63}$")
    private val CURRENCY = Regex("^[A-Za-z]{3}$")
    const val MAX_PROPERTIES = 20
    const val MAX_STRING = 200

    fun isValidName(name: String) = NAME.matches(name)

    fun timestamp(millis: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date(millis))

    /** Keeps string (trimmed to 200), number and boolean values; anything else is dropped with a warning. */
    fun properties(input: Map<String, Any?>?, log: Logger): JSONObject? {
        if (input.isNullOrEmpty()) return null
        val out = JSONObject()
        for ((key, value) in input) {
            if (out.length() >= MAX_PROPERTIES) {
                log.warn("Only the first $MAX_PROPERTIES event properties are kept.")
                break
            }
            if (key.isEmpty() || key.length > 64) {
                log.warn("Property name \"$key\" must be 1-64 characters; dropped.")
                continue
            }
            when (value) {
                is String -> out.put(key, value.take(MAX_STRING))
                is Boolean -> out.put(key, value)
                is BigDecimal -> out.put(key, value)
                is Int, is Long, is Short, is Byte -> out.put(key, (value as Number).toLong())
                is Double -> if (value.isFinite()) out.put(key, value) else log.warn("Property \"$key\" is not a finite number; dropped.")
                is Float -> if (value.isFinite()) out.put(key, value.toDouble()) else log.warn("Property \"$key\" is not a finite number; dropped.")
                null -> {}
                else -> log.warn("Property \"$key\" must be a string, number or boolean; dropped.")
            }
        }
        return if (out.length() == 0) null else out
    }

    /** "49.99" from BigDecimal; null when negative or more precise than 6 decimals. */
    fun amount(amount: BigDecimal): String? {
        if (amount.signum() < 0) return null
        val plain = amount.stripTrailingZeros()
        if (plain.scale() > 6) return null
        return plain.setScale(maxOf(plain.scale(), 0)).toPlainString()
    }

    fun isValidCurrency(currency: String) = CURRENCY.matches(currency)

    fun event(id: String, name: String, timestampMillis: Long, properties: JSONObject?, revenue: Pair<String, String>?): JSONObject =
        JSONObject().apply {
            put("id", id)
            put("name", name)
            put("timestamp", timestamp(timestampMillis))
            if (properties != null) put("properties", properties)
            if (revenue != null) put("revenue", JSONObject().put("amount", revenue.first).put("currency", revenue.second.uppercase(Locale.US)))
        }

    fun install(installId: String, device: DeviceInfo, referrer: ReferrerDetails?, userId: String?): String = JSONObject().apply {
        put("installId", installId)
        userId?.let { put("userId", it) }
        put("platform", device.platform)
        put("sdk", JSONObject().put("name", device.sdkName).put("version", device.sdkVersion))
        device.osVersion?.let { put("osVersion", it.take(32)) }
        device.appVersion?.let { put("appVersion", it.take(32)) }
        device.deviceClass?.let { put("deviceClass", it) }
        device.locale?.let { put("locale", it.take(35)) }
        put("isDebug", device.isDebug)
        if (referrer != null) {
            put("playReferrer", JSONObject().apply {
                put("raw", referrer.raw.take(4096))
                if (referrer.clickAtSeconds > 0) put("clickAt", referrer.clickAtSeconds)
                if (referrer.installBeginAtSeconds > 0) put("installBeginAt", referrer.installBeginAtSeconds)
            })
        }
    }.toString()

    fun events(installId: String, events: List<String>, userId: String?): String =
        "{\"installId\":${JSONObject.quote(installId)}," +
            (if (userId != null) "\"userId\":${JSONObject.quote(userId)}," else "") +
            "\"events\":[${events.joinToString(",")}]}"

    /** The deferred deep link from an /v1/install response, when the install was attributed to a link. */
    fun deepLinkFromInstall(body: String?): UnolinkDeepLink? {
        val attribution = runCatching { JSONObject(body ?: return null).getJSONObject("attribution") }.getOrNull() ?: return null
        if (attribution.optString("status") != "attributed") return null
        val clickId = attribution.optStringOrNull("clickId") ?: return null
        val params = attribution.optJSONObject("params")?.let { p -> p.keys().asSequence().associateWith { p.optString(it) } } ?: emptyMap()
        val link = attribution.optJSONObject("link")
        return UnolinkDeepLink(attribution.optStringOrNull("deepLink"), params, link?.optStringOrNull("slug"), clickId)
    }

    /** The code of an error response (RFC 9457 problem details), e.g. "install_required". */
    fun problemCode(body: String?): String? = runCatching { JSONObject(body ?: return null).optStringOrNull("code") }.getOrNull()

    private fun JSONObject.optStringOrNull(key: String): String? = if (isNull(key)) null else optString(key).ifEmpty { null }
}

/** What Google Play's Install Referrer API returned. */
internal class ReferrerDetails(val raw: String, val clickAtSeconds: Long = 0, val installBeginAtSeconds: Long = 0) {
    /**
     * The deferred deep link written into the referrer by Unolink's redirect (unolink_click_id, unolink_link,
     * unolink_deep_link, unolink_p_*), available without waiting for the network. Null for installs that didn't come
     * through a Unolink link.
     */
    fun deepLink(): UnolinkDeepLink? {
        val values = LinkedHashMap<String, String>()
        for (pair in raw.trimStart('?').split('&')) {
            if (pair.isEmpty()) continue
            val parts = pair.split('=', limit = 2)
            values[decode(parts[0])] = if (parts.size == 2) decode(parts[1]) else ""
        }
        val clickId = values["unolink_click_id"]?.takeIf { CLICK_ID.matches(it) } ?: return null
        val params = values.filterKeys { it.startsWith("unolink_p_") }.mapKeys { it.key.removePrefix("unolink_p_") }
        return UnolinkDeepLink(values["unolink_deep_link"]?.ifEmpty { null }, params, values["unolink_link"]?.ifEmpty { null }, clickId)
    }

    private fun decode(s: String): String = runCatching { URLDecoder.decode(s, "UTF-8") }.getOrDefault(s)

    private companion object {
        val CLICK_ID = Regex("^clk_[0-9A-HJKMNP-TV-Z]{26}$")
    }
}
