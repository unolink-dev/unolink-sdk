# Unolink SDKs

Open-source SDKs for [Unolink](https://unolink.dev): see which link or ad brings installs, onboarding, paywall
views, trials and purchases, and send people who install from a link straight to the right screen.

| Platform | Status | Install |
|---|---|---|
| Android (Kotlin, Java) | 0.2.0, beta | Maven Central: `dev.unolink:unolink:0.2.0` |
| iOS (Swift, Objective-C) | 0.2.0, beta | Swift Package Manager: `https://github.com/unolink-dev/unolink-sdk` |
| React Native / Expo | 0.2.0, beta | npm: `@unolink/react-native` |
| Flutter | 0.2.0, beta | pub.dev: `unolink` |

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
