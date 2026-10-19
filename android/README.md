# Unolink Android SDK

Kotlin, callable from Java. minSdk 23. Dependencies: Google's Play Install Referrer library and AndroidX
`lifecycle-process`, nothing else.

```kotlin
// build.gradle.kts
implementation("dev.unolink:unolink:0.2.1")
```

```kotlin
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        Unolink.configure(this, "ulk_…") // your app's SDK key (Unolink → your app → Settings → API keys)
        Unolink.setDeferredDeepLinkListener { link -> /* open link.deepLink */ }
    }
}

Unolink.onboardingStep("goal", index = 0)                // in a LaunchedEffect of each onboarding screen
Unolink.onboardingSkipped("goal")
Unolink.onboardingCompleted()
Unolink.paywallViewed()
Unolink.paywallSkipped()
Unolink.trialStarted(productId = "pro_yearly")
Unolink.purchase(BigDecimal("49.99"), "USD", productId = "pro_yearly")
Unolink.track("level_up", mapOf("level" to 3))
```

Onboarding: call `onboardingStep` when each screen appears (not from its button), `onboardingSkipped` on Skip, then
`onboardingCompleted`. The dashboard shows which screen people leave on. Step events are free. Screen IDs are fixed
names such as `goal`, never user data.

Java: `Unolink.configure(this, "ulk_…")`, `Unolink.purchase(new BigDecimal("49.99"), "USD")`, and so on.

## How it behaves

- First launch: reads Google Play's install referrer, registers the install, and calls your deferred deep link
  listener once if the install came from a Unolink link.
- Automatic events: `first_open`, `session_start` (launch, or after 30 minutes in the background), `app_background`.
- Events are queued on disk (up to 1,000), sent in batches of up to 100 every 15 seconds while the app is open, at 20
  queued events, and when the app goes to the background. Offline? They wait and retry with backoff.
- Never blocks, never throws, never uses the Advertising ID.
- `Unolink.setEnabled(false)` turns tracking off and deletes queued events (for your opt-out setting).

## Developing

```bash
cd android
./gradlew :unolink:testDebugUnitTest      # unit + contract-schema tests (JVM, no emulator)
./gradlew :samples:kotlin:installDebug    # sample app on a running emulator or phone
```

The sample reads `unolink.sampleKey` and `unolink.baseUrl` from `android/local.properties` (not committed). Requires
JDK 17+ (Android Studio's bundled JDK works: `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`).
