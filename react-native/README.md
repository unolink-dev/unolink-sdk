# @unolink/react-native

Unolink for React Native and Expo (new architecture, React Native 0.79+). A thin bridge over the native Unolink iOS and
Android SDKs, which ship inside this package. **No config plugin is needed**: no permissions beyond internet, no
Info.plist entries. It doesn't run in Expo Go (it has native code): use a development build.

```bash
npx expo install @unolink/react-native     # Expo (then rebuild: npx expo prebuild / eas build)
npm install @unolink/react-native          # bare React Native (then cd ios && LANG=en_US.UTF-8 pod install)
```

Install notes:

- **CocoaPods needs a UTF-8 locale.** With Ruby 4, or a shell without a UTF-8 locale (some CI images and terminals),
  `pod install` fails with an encoding error. Run it as `LANG=en_US.UTF-8 pod install` (or `export LANG=en_US.UTF-8`
  in your shell profile / CI environment first). `npx expo prebuild` and `npx expo run:ios` run `pod install` for you,
  so set `LANG` before those too.
- **Don't use `npm install --legacy-peer-deps`.** It rewrites `package-lock.json` and drops optional peer
  dependencies, which can break other native packages in the app. Use `npx expo install` (Expo) or a plain
  `npm install`.

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
Unolink.connectRevenueCat(Purchases)                    // RevenueCat's user ID, kept current (see below)
Unolink.purchase("49.99", "USD", "pro_yearly")          // not needed if RevenueCat is connected to Unolink
Unolink.track("level_up", { level: 3 })
```

Calls never throw. Calls made before `configure` wait and are sent right after it, so restoring a session first is
fine. Without the native module (Expo Go, Jest, web) every call does nothing. `Unolink.isConfigured()` says whether it's
running.

## RevenueCat

Unolink joins RevenueCat's purchases, renewals and refunds to the install by RevenueCat's app user ID. Let the SDK keep
it current (0.3.2+; no dependency on react-native-purchases, you pass its `Purchases`):

```ts
import Purchases from "react-native-purchases"

Unolink.connectRevenueCat(Purchases)   // once, before or after configure; returns a function that disconnects
```

The ID (`Purchases.getAppUserID()`) is read now, on every customer info update (purchases, `logIn`, `logOut`) and
whenever the app comes back to the foreground, and sent only when it changed, so a guest's purchase under RevenueCat's
anonymous ID counts too. If RevenueCat isn't configured yet, the read fails quietly and is tried again.

Without it: `Unolink.setUserId(await Purchases.getAppUserID())` after configuring RevenueCat, after every `logIn` /
`logOut`, and on every launch. Use one or the other. Unolink stores only a keyed hash of the ID.

## Deferred deep links (Android)

`link.deepLink` is what you set on the link: a path such as `/promo/3for2`, or a full URL. If the screen sits behind
onboarding or sign-in, open it when that's done, then consume it:

```ts
// after onboarding / sign-in (and on every launch after that, until it's consumed):
const link = Unolink.getPendingDeferredDeepLink()
if (link?.deepLink) {
  router.push(link.deepLink)                     // a path; open full URLs with Linking.openURL
  Unolink.consumeDeferredDeepLink()
}
```

The pending link is kept on the device until you call `consumeDeferredDeepLink()` (0.3.3+), so a new user who quits
mid-onboarding still gets it on the next launch: you don't need to store it yourself. It's kept for at most 30 days
after the install, then dropped.

If the screen is reachable straight away, a listener is enough. A link that arrives before you subscribe goes to the
first listener you add:

```ts
Unolink.addDeferredDeepLinkListener((link) => {
  if (link.deepLink) router.push(link.deepLink)
  Unolink.consumeDeferredDeepLink()
})
```

How the two fit together:

- Listeners are called **once per install** (on the launch the link becomes known, or the first launch after that with
  a listener), never again on later launches, so a link isn't opened twice.
- `getPendingDeferredDeepLink()` returns the link on **every launch until it's consumed**, whether or not a listener
  already received it. It's null before `configure()` and until Google Play has answered (a second or two on the first
  launch; the listener tells you when it's known).
- Always call `consumeDeferredDeepLink()` once you've opened the link. If you never call it, listeners behave as before
  (once per install), but `getPendingDeferredDeepLink()` keeps returning the link for 30 days.
- iPhone has no install referrer, so there's normally nothing to deliver: the calls are safe and return null.

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
