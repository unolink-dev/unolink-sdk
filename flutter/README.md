# unolink (Flutter)

Unolink for Flutter. A thin layer over the native Unolink iOS and Android SDKs, which ship inside this package.

```yaml
dependencies:
  unolink: ^0.3.3
```

iOS: CocoaPods needs a UTF-8 locale. With Ruby 4, or a shell without one (some CI images), `pod install` (and
`flutter run` / `flutter build ios`, which run it) fails with an encoding error: run `export LANG=en_US.UTF-8` first,
or `cd ios && LANG=en_US.UTF-8 pod install`.

```dart
import 'package:flutter/foundation.dart';
import 'package:unolink/unolink.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Unolink.configure('ulk_…', debug: kDebugMode);
  Unolink.setDeferredDeepLinkListener((link) {
    router.go(link.deepLink ?? '/');
    Unolink.consumeDeferredDeepLink();
  });
  runApp(const MyApp());
}

Unolink.onboardingStep('goal', index: 0);                // in initState of each onboarding screen
Unolink.onboardingSkipped('goal');
Unolink.onboardingCompleted();
Unolink.paywallViewed(placement: 'onboarding');
Unolink.paywallSkipped(placement: 'onboarding');
Unolink.signUp(method: 'apple');               // a new account
Unolink.signIn(method: 'apple');               // a returning user signed in
Unolink.signUpSkipped();                       // continued as a guest
Unolink.purchase('49.99', 'USD', productId: 'pro_yearly'); // not needed if RevenueCat is connected to Unolink
Unolink.track('level_up', {'level': 3});
```

Onboarding: call `onboardingStep` when each screen appears (not from its button), `onboardingSkipped` on Skip, then
`onboardingCompleted`. The dashboard shows which screen people leave on. Step events are free. Screen IDs are fixed
names such as `goal`, never user data.

## Deferred deep links (Android)

`link.deepLink` is what you set on the link: a path such as `/promo/3for2`, or a full URL. If the screen sits behind
onboarding or sign-in, open it when that's done, then consume it:

```dart
// after onboarding / sign-in (and on every launch after that, until it's consumed):
final link = await Unolink.getPendingDeferredDeepLink();
if (link?.deepLink != null) {
  router.go(link!.deepLink!);
  await Unolink.consumeDeferredDeepLink();
}
```

The pending link is kept on the device until you call `consumeDeferredDeepLink()` (0.3.3+), so a new user who quits
mid-onboarding still gets it on the next launch. It's kept for at most 30 days after the install, then dropped.

- The listener (`setDeferredDeepLinkListener`) is called **once per install**, never again on later launches, so a link
  isn't opened twice. A link that arrives before you set it goes to the listener when you set it.
- `getPendingDeferredDeepLink()` returns the link on **every launch until it's consumed**, whether or not the listener
  already received it. It's null before `configure` and until Google Play has answered.
- Always call `consumeDeferredDeepLink()` once you've opened the link (from the listener too). If you never call it, the
  listener behaves as before, but `getPendingDeferredDeepLink()` keeps returning the link for 30 days.
- iPhone has no install referrer, so there's normally nothing to deliver: the calls are safe and return null.

## RevenueCat

Unolink joins RevenueCat's purchases, renewals and refunds to the install by RevenueCat's app user ID. Let the SDK keep
it current (0.3.2+; no dependency on RevenueCat, you pass its functions):

```dart
Unolink.connectRevenueCat(
  () => Purchases.appUserID,
  addListener: Purchases.addCustomerInfoUpdateListener,
  removeListener: Purchases.removeCustomerInfoUpdateListener,
);
```

Call it once, before or after `configure`. The ID is read once configured, on every customer info update (purchases,
`logIn`, `logOut`) and whenever the app resumes, and sent only when it changed, so a guest's purchase under RevenueCat's
anonymous ID counts too. It returns a function that disconnects.

Without it: `Unolink.setUserId(await Purchases.appUserID)` after configuring RevenueCat, after every `logIn` / `logOut`,
and on every launch. Use one or the other. Unolink stores only a keyed hash of the ID.

No extra setup on iOS or Android: the SDK needs no permissions beyond internet and no Info.plist entries.

## Developing

`tool/sync_native.sh` copies the native SDK cores into the plugin (run it after changing either SDK, and before
publishing). The example app talks to UAT:

```bash
cd example && flutter run --dart-define=UNOLINK_KEY=ulk_…
```

To do before 1.0: migrate the Android build to Flutter's built-in Kotlin (needs Flutter 3.44+ and AGP 9).
