# @unolink/react-native

Unolink for React Native and Expo (new architecture, React Native 0.79+). A thin bridge over the native Unolink iOS and
Android SDKs, which ship inside this package. **No config plugin is needed**: no permissions beyond internet, no
Info.plist entries. It doesn't run in Expo Go (it has native code): use a development build.

```bash
npx expo install @unolink/react-native     # Expo (then rebuild: npx expo prebuild / eas build)
npm install @unolink/react-native          # bare React Native (then cd ios && pod install)
```

```ts
import { Unolink, useOnboardingStep } from "@unolink/react-native"

Unolink.configure(process.env.EXPO_PUBLIC_UNOLINK_KEY!)  // once, early (root layout); test device in dev builds by default

useOnboardingStep("goal", { index: 0 })                 // in each onboarding screen (or Unolink.onboardingStep)
Unolink.onboardingSkipped("goal")
Unolink.onboardingCompleted()
Unolink.paywallViewed("onboarding")
Unolink.paywallSkipped("onboarding")                   // closed without buying: button, swipe-down or back
Unolink.signUp("apple")                                 // a new account
Unolink.signIn("apple")                                 // a returning user signed in
Unolink.signUpSkipped()                                 // continued as a guest
Unolink.setUserId(revenueCatAppUserId)                  // the ID you pass to Purchases.logIn
Unolink.purchase("49.99", "USD", "pro_yearly")          // not needed if RevenueCat is connected to Unolink
Unolink.track("level_up", { level: 3 })
```

Calls never throw. Calls made before `configure` wait and are sent right after it, so restoring a session first is
fine. Without the native module (Expo Go, Jest, web) every call does nothing. `Unolink.isConfigured()` says whether it's
running.

## Deferred deep links (Android)

`link.deepLink` is what you set on the link: a path such as `/promo/3for2`, or a full URL. If the screen sits behind
onboarding or sign-in, hold it and open it when that's done:

```ts
// after onboarding / sign-in:
const link = Unolink.getPendingDeferredDeepLink()
if (link?.deepLink) {
  Unolink.consumeDeferredDeepLink()
  router.push(link.deepLink)                     // a path; open full URLs with Linking.openURL
}
```

If the screen is reachable straight away, a listener is enough. A link that arrives before you subscribe goes to the
first listener you add:

```ts
Unolink.addDeferredDeepLinkListener((link) => link.deepLink && router.push(link.deepLink))
```

## Onboarding

Call `useOnboardingStep` / `onboardingStep` when each screen appears (not from its button), `onboardingSkipped` on Skip,
then `onboardingCompleted`. Step events are free. Screen IDs are fixed names such as `goal` (letters, digits, `_` and `.`;
no `-`), never user data. Development builds warn in the console about anything the server would reject.

## Tests (Jest)

```ts
jest.mock("@unolink/react-native", () => require("@unolink/react-native/jest"))
// expect(Unolink.signUp).toHaveBeenCalledWith("apple")
```

Docs: <https://unolink.dev/docs>.
