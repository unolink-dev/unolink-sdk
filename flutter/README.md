# unolink (Flutter)

Unolink for Flutter. A thin layer over the native Unolink iOS and Android SDKs, which ship inside this package.

```yaml
dependencies:
  unolink: ^0.1.0
```

```dart
import 'package:flutter/foundation.dart';
import 'package:unolink/unolink.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Unolink.configure('ulk_…', debug: kDebugMode);
  Unolink.setDeferredDeepLinkListener((link) => router.go(link.deepLink ?? '/'));
  runApp(const MyApp());
}

Unolink.onboardingStep('goal', index: 0);                // in initState of each onboarding screen
Unolink.onboardingSkipped('goal');
Unolink.onboardingCompleted();
Unolink.paywallViewed(placement: 'onboarding');
Unolink.paywallSkipped(placement: 'onboarding');
Unolink.signUp(method: 'apple');
Unolink.setUserId(revenueCatAppUserId);                  // the ID you pass to Purchases.logIn
Unolink.purchase('49.99', 'USD', productId: 'pro_yearly'); // not needed if RevenueCat is connected to Unolink
Unolink.track('level_up', {'level': 3});
```

Onboarding: call `onboardingStep` when each screen appears (not from its button), `onboardingSkipped` on Skip, then
`onboardingCompleted`. The dashboard shows which screen people leave on. Step events are free. Screen IDs are fixed
names such as `goal`, never user data.

No extra setup on iOS or Android: the SDK needs no permissions beyond internet and no Info.plist entries.

## Developing

`tool/sync_native.sh` copies the native SDK cores into the plugin (run it after changing either SDK, and before
publishing). The example app talks to UAT:

```bash
cd example && flutter run --dart-define=UNOLINK_KEY=ulk_…
```

To do before 1.0: migrate the Android build to Flutter's built-in Kotlin (needs Flutter 3.44+ and AGP 9).
