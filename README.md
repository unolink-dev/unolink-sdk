# Unolink SDKs

Open-source SDKs for [Unolink](https://unolink.dev): see which link or ad brings installs, onboarding, paywall
views, trials and purchases, and send people who install from a link straight to the right screen.

| Platform | Status | Install |
|---|---|---|
| Android (Kotlin, Java) | 0.3.3, beta | Maven Central: `dev.unolink:unolink:0.3.3` |
| iOS (Swift, Objective-C) | 0.3.3, beta | Swift Package Manager: `https://github.com/unolink-dev/unolink-sdk` |
| React Native / Expo | 0.3.3, beta | npm: `@unolink/react-native` |
| Flutter | 0.3.3, beta | pub.dev: `unolink` |

Install notes (React Native, Expo, Flutter):

- **CocoaPods needs a UTF-8 locale.** With Ruby 4, or a shell without a UTF-8 locale, `pod install` fails with an
  encoding error: run `LANG=en_US.UTF-8 pod install` (or `export LANG=en_US.UTF-8` before `npx expo prebuild`,
  `npx expo run:ios` or `flutter build ios`).
- **Don't use `npm install --legacy-peer-deps`.** It rewrites `package-lock.json` and drops optional peer dependencies.
  Use `npx expo install @unolink/react-native` (Expo) or a plain `npm install`.

Deferred deep links (Android) stay pending on the device until the app calls `consumeDeferredDeepLink()` (30 days at
most), so a new user who quits mid-onboarding still gets theirs on the next launch. See each SDK's README.

## What the SDK collects

- A **random install ID**, created on first launch and stored only in your app's own storage. A reinstall gets a new
  one. It is never linked to a person, an advertising ID or the device.
- App version, OS version, SDK version, phone or tablet, language.
- The events you send (`onboardingStep`, `onboardingCompleted`, `paywallViewed`, `trialStarted`, `purchase`, your own) with the
  properties you choose, plus three automatic ones: first open, session start, app to background.
- On Android, the Google Play install referrer, which says which Unolink link someone installed from.

It does **not** collect the IDFA or Google Advertising ID, never shows the App Tracking Transparency prompt, and never
fingerprints devices. Country comes from Cloudflare at the edge; IP addresses are not stored.

## Repository layout

```
contract/   The SDK API contract: plain-language spec, OpenAPI, JSON Schemas, test scenarios
android/    Android SDK (Kotlin) + Kotlin and Java sample apps
ios/        iOS SDK (Swift) + SwiftUI and Objective-C samples
react-native/  React Native / Expo bridge (@unolink/react-native)
flutter/    Flutter plugin (unolink) + example app
```

Docs: <https://unolink.dev/docs>. Licence: MIT.
