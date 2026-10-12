# Unolink iOS SDK

Swift, callable from Objective-C. iOS 13+. No dependencies. Includes a privacy manifest (no tracking, no IDFA, no ATT
prompt; analytics data not linked to the user's identity).

**Install:** Xcode → File → Add Package Dependencies → `https://github.com/unolink-dev/unolink-sdk` → library **Unolink**.

```swift
import Unolink

@main
struct MyApp: App {
    init() {
        #if DEBUG
        Unolink.configure(apiKey: "ulk_…", options: UnolinkOptions(debug: true))
        #else
        Unolink.configure(apiKey: "ulk_…")
        #endif
    }
    // …
}

Unolink.onboardingCompleted()
Unolink.paywallViewed(placement: "onboarding")
Unolink.paywallSkipped(placement: "onboarding")
Unolink.signUp(method: "apple")
Unolink.setUserId(revenueCatAppUserId)            // stored by Unolink only as a keyed hash
Unolink.trialStarted(productId: "pro_yearly")
Unolink.purchase(amount: product.price, currency: "USD", productId: product.id)   // amount: Decimal
Unolink.purchaseCancelled(productId: product.id)
Unolink.track("level_up", properties: ["level": 3])
```

Objective-C: `[Unolink configureWithApiKey:@"ulk_…" options:[UNLOptions new]];`,
`[Unolink paywallViewedWithPlacement:@"onboarding" properties:nil];`,
`[Unolink purchaseWithAmount:[NSDecimalNumber decimalNumberWithString:@"49.99"] currency:@"USD" productId:nil properties:nil];`

## How it behaves

- First launch: creates a random install ID (in Application Support, excluded from iCloud backup, never the Keychain,
  so a reinstall or a new phone is a new install) and registers the install. `Unolink.installId` is available as soon
  as `configure` returns.
- iPhone installs are **not** attributed to a link per person: Apple has no install referrer, and Unolink never
  fingerprints. Installs and every event are still counted exactly.
- Automatic events: `first_open`, `session_start` (launch, or after 30 minutes in the background), `app_background`.
- Events are queued on disk (up to 1,000), sent in batches of up to 100 every 15 seconds while the app is active, at
  20 queued events, and when the app goes to the background. Offline? They wait and retry with backoff.
- Never blocks the main thread, never throws.

## Developing

```bash
swift test                                   # from the repo root: unit + contract-schema tests
cd ios/Examples && xcodegen && open UnolinkExamples.xcodeproj   # SwiftUI and Objective-C samples
```

The samples read your SDK key from `ios/Examples/Secrets.xcconfig` (not committed): `UNOLINK_KEY = ulk_…`. They talk
to UAT and mark themselves as test devices. Launch argument `-unolinkAutoRun` fires every sample event once.
