# Unolink Android SDK

Kotlin, callable from Java. minSdk 23. Dependencies: Google's Play Install Referrer library and AndroidX
`lifecycle-process`, nothing else.

```kotlin
// build.gradle.kts
implementation("dev.unolink:unolink:0.3.3")
```

```kotlin
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        Unolink.configure(this, "ulk_…") // your app's SDK key (Unolink → your app → Settings → API keys)
        Unolink.setDeferredDeepLinkListener { link -> /* open link.deepLink */ Unolink.consumeDeferredDeepLink() }
    }
}

Unolink.onboardingStep("goal", index = 0)                // in a LaunchedEffect of each onboarding screen
Unolink.onboardingSkipped("goal")
Unolink.onboardingCompleted()
Unolink.paywallViewed()
Unolink.paywallSkipped()
Unolink.signUp("google")                                 // a new account
Unolink.signIn("google")                                 // a returning user signed in
Unolink.signUpSkipped()                                  // continued as a guest
Unolink.connectRevenueCat { Purchases.sharedInstance.appUserID }   // see RevenueCat below
Unolink.trialStarted(productId = "pro_yearly")
Unolink.purchase(BigDecimal("49.99"), "USD", productId = "pro_yearly")
Unolink.track("level_up", mapOf("level" to 3))
```

Onboarding: call `onboardingStep` when each screen appears (not from its button), `onboardingSkipped` on Skip, then
`onboardingCompleted`. The dashboard shows which screen people leave on. Step events are free. Screen IDs are fixed
names such as `goal`, never user data.

## RevenueCat

Unolink joins RevenueCat's purchases, renewals and refunds to the install by RevenueCat's app user ID. Let the SDK keep
it current (0.3.2+; no dependency on RevenueCat, you pass a lambda that reads the ID):

```kotlin
Unolink.connectRevenueCat { Purchases.sharedInstance.appUserID }
```

Call it once, before or after `configure` (e.g. in `Application.onCreate`). The ID is read at `configure`, whenever the
app comes to the foreground and before each event, and sent only when it changed, so a guest's purchase under
RevenueCat's anonymous ID counts too. If RevenueCat isn't configured yet, the read fails quietly and is tried again.
After `logIn` / `logOut`, call `Unolink.revenueCatUserChanged()` to send the new ID at once.

Without it: `Unolink.setUserId(Purchases.sharedInstance.appUserID)` after configuring RevenueCat, after every `logIn` /
`logOut`, and on every launch. Use one or the other. Unolink stores only a keyed hash of the ID.

Java: `Unolink.connectRevenueCat(() -> Purchases.getSharedInstance().getAppUserID())`.

Java: `Unolink.configure(this, "ulk_…")`, `Unolink.purchase(new BigDecimal("49.99"), "USD")`, and so on.

## How it behaves

- First launch: reads Google Play's install referrer, registers the install, and calls your deferred deep link
  listener once if the install came from a Unolink link.
- Deferred deep link: the listener is called once per install. The link is also kept on the device until you call
  `Unolink.consumeDeferredDeepLink()` (at most 30 days): if its screen sits behind onboarding or sign-in, read
  `Unolink.getPendingDeferredDeepLink()` when that's done, open it, then consume it. It survives app restarts, so a user
  who quits mid-onboarding still gets it next time. Always consume a link you've opened.
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
