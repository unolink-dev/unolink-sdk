# @unolink/react-native

Unolink for React Native and Expo (new architecture, React Native 0.79+). A thin bridge over the native Unolink iOS and
Android SDKs, which ship inside this package.

```bash
npx expo install @unolink/react-native     # Expo (then rebuild: npx expo prebuild / eas build)
npm install @unolink/react-native          # bare React Native (then pod install)
```

```ts
import { Unolink, useOnboardingStep } from "@unolink/react-native"

Unolink.configure("ulk_…", { debug: __DEV__ })          // once, early (root layout)
Unolink.addDeferredDeepLinkListener((link) => router.push(link.deepLink ?? "/"))

useOnboardingStep("goal", { index: 0 })                 // in each onboarding screen (or Unolink.onboardingStep)
Unolink.onboardingSkipped("goal")
Unolink.onboardingCompleted()
Unolink.paywallViewed("onboarding")
Unolink.paywallSkipped("onboarding")
Unolink.signUp("apple")
Unolink.setUserId(revenueCatAppUserId)                   // the ID you pass to Purchases.logIn
Unolink.purchase("49.99", "USD", "pro_yearly")           // not needed if RevenueCat is connected to Unolink
Unolink.track("level_up", { level: 3 })
```

Onboarding: call `useOnboardingStep` / `onboardingStep` when each screen appears (not from its button), `onboardingSkipped` on Skip, then
`onboardingCompleted`. The dashboard shows which screen people leave on. Step events are free. Screen IDs are fixed
names such as `goal`, never user data.

No config plugin is needed: the SDK needs no permissions beyond internet and no Info.plist entries. Docs:
<https://unolink.dev/docs>.
