package dev.unolink.sample

import android.app.Activity
import android.os.Bundle
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import dev.unolink.Unolink
import java.math.BigDecimal

/** One button per SDK call, plus what the SDK knows about this install. */
class MainActivity : Activity() {
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(48, 96, 48, 48) }
        status = TextView(this).apply { textSize = 13f; setPadding(0, 0, 0, 32) }
        column.addView(TextView(this).apply { text = "Unolink sample"; textSize = 24f })
        column.addView(status)

        fun button(label: String, action: () -> Unit) = column.addView(Button(this).apply {
            text = label
            setOnClickListener { action(); refresh("Sent: $label") }
        }, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        button("Onboarding completed") { Unolink.onboardingCompleted(mapOf("steps" to 4)) }
        button("Paywall viewed") { Unolink.paywallViewed(mapOf("paywall" to "main")) }
        button("Paywall skipped") { Unolink.paywallSkipped() }
        button("Trial started") { Unolink.trialStarted(productId = "pro_yearly") }
        button("Purchase 4.99 USD") { Unolink.purchase(BigDecimal("4.99"), "USD", productId = "pro_monthly") }
        button("Custom event: level_up") { Unolink.track("level_up", mapOf("level" to 3)) }
        button("Send now (flush)") { Unolink.flush() }

        setContentView(ScrollView(this).apply { addView(column, MATCH_PARENT, WRAP_CONTENT) })
    }

    override fun onResume() {
        super.onResume()
        refresh(null)
    }

    private fun refresh(note: String?) {
        val link = SampleApp.lastDeepLink
        status.text = buildString {
            appendLine("API: ${BuildConfig.UNOLINK_BASE_URL}")
            appendLine("Key: ${BuildConfig.UNOLINK_KEY.take(12).ifEmpty { "(missing: set unolink.sampleKey in local.properties)" }}…")
            appendLine("Install ID: ${Unolink.getInstallId()}")
            appendLine("Deferred deep link: ${link?.let { "${it.deepLink} ${it.params} via /${it.linkSlug ?: ""}" } ?: "none"}")
            if (note != null) appendLine(note)
        }
    }
}
