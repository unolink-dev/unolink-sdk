## 0.3.1

* `setUserId(null)` now tells Unolink the user signed out: the install has no current user, and purchases from the IDs it reported before still count for it.
* The dashboard keeps every user ID an install reported, so a guest who buys and then creates an account keeps the purchase and its renewals.

## 0.3.0

* `signIn(method:)` when someone signs in to an account they already had, so the dashboard can tell returning users from new sign-ups (`signUp`).
* iPhone: TestFlight and Xcode builds are test devices automatically (they carry a sandbox receipt).
* Android: release builds installed by their developer (adb, Android Studio) are test devices automatically. Google Play testing tracks can't be told apart on the phone: pass `debug: true` in those builds.

## 0.2.1

* iPhone: numbers 0 and 1 passed from Flutter (or React Native) were sent as false/true, so `onboardingStep(index: 0)` and `index: 1` were refused and their screens didn't show. They're sent as numbers now.

## 0.2.0

* `onboardingStep(step, index:, flow:)` when an onboarding screen appears and `onboardingSkipped(...)` when someone skips it. Both are free (they don't count toward your events) and show where people leave your onboarding.
* Error messages point to where SDK keys now live in the dashboard: your app → Settings → API keys.

## 0.1.1

* Android: Google's test phones (Play pre-launch reports, Firebase Test Lab) are always marked as test devices, so they're left out of your numbers by default.

## 0.1.0

* First release: install attribution (Google Play install referrer), deferred deep links with link parameters on Android, funnel events (onboarding, paywall, sign-up, trial, purchase), user IDs for RevenueCat, iOS and Android.
