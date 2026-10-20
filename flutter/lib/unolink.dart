/// Unolink for Flutter: which link or ad brings installs, onboarding, paywall views, trials and purchases.
///
/// A thin layer over the native Unolink iOS and Android SDKs (shipped inside this package). Calls never throw and
/// never block: events are queued on the device and sent in the background.
library;

import 'package:flutter/services.dart';

/// Where to take someone who just installed from a Unolink link (Android; iPhone only when attributed with certainty).
class UnolinkDeepLink {
  const UnolinkDeepLink({required this.deepLink, required this.params, required this.linkSlug, required this.clickId});

  /// The link's deep link, e.g. "/promo/3for2", or null.
  final String? deepLink;

  /// The link's parameters.
  final Map<String, String> params;

  /// The campaign link's path (e.g. "tiktok"), or null for the app's main link.
  final String? linkSlug;

  final String clickId;

  static UnolinkDeepLink fromMap(Map<Object?, Object?> map) => UnolinkDeepLink(
        deepLink: map['deepLink'] as String?,
        params: ((map['params'] as Map<Object?, Object?>?) ?? const {}).map((k, v) => MapEntry('$k', '$v')),
        linkSlug: map['linkSlug'] as String?,
        clickId: map['clickId'] as String,
      );
}

enum UnolinkLogLevel { none, error, warn, info, debug }

class Unolink {
  Unolink._();

  /// This package's version (sent with every install as the SDK version).
  static const String version = '0.3.0';

  static const MethodChannel _channel = MethodChannel('dev.unolink/sdk');
  static void Function(UnolinkDeepLink link)? _deepLinkListener;
  static UnolinkDeepLink? _pendingDeepLink;

  /// Call once, as early as possible (e.g. in main() after WidgetsFlutterBinding.ensureInitialized()).
  ///
  /// [apiKey] is your app's SDK key (fine to ship in the app). Pass [debug]: kDebugMode so test devices are hidden
  /// in the dashboard unless "Include test devices" is on. Use baseUrl "https://api-uat.unolink.dev" while testing.
  static Future<void> configure(String apiKey, {String? baseUrl, UnolinkLogLevel logLevel = UnolinkLogLevel.warn, bool debug = false}) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeferredDeepLink') {
        final link = UnolinkDeepLink.fromMap(call.arguments as Map<Object?, Object?>);
        final listener = _deepLinkListener;
        if (listener != null) {
          listener(link);
        } else {
          _pendingDeepLink = link;
        }
      }
    });
    await _invoke('configure', {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'logLevel': logLevel.name,
      'debug': debug,
      'sdkVersion': version,
    });
  }

  /// Your own event, e.g. track('level_up', {'level': 3}). Values: strings, numbers or booleans.
  static Future<void> track(String name, [Map<String, Object>? properties]) =>
      _invoke('track', {'name': name, 'properties': properties});

  /// The user finished the onboarding screens (send it before any paywall or sign-up that follows them).
  static Future<void> onboardingCompleted([Map<String, Object>? properties]) => track('onboarding_completed', properties);

  /// An onboarding screen appeared. Call it when the screen shows (initState), not from its button. step is a fixed
  /// screen ID such as 'goal', never user data; index its position (0, 1, 2…); flow which onboarding, if you run more
  /// than one. Free: an onboarding costs one event (its onboardingCompleted) however many screens it has.
  static Future<void> onboardingStep(String step, {int? index, String? flow}) =>
      track('onboarding_step', _onboarding(step, index, flow));

  /// The user tapped Skip on the onboarding screen step. Free, like onboardingStep.
  static Future<void> onboardingSkipped(String step, {int? index, String? flow}) =>
      track('onboarding_skipped', _onboarding(step, index, flow));

  /// A paywall was shown. placement: "onboarding", "feature_gate", or your own name.
  static Future<void> paywallViewed({String? placement, Map<String, Object>? properties}) =>
      track('paywall_viewed', _with('placement', placement, properties));

  /// The user closed a paywall without buying.
  static Future<void> paywallSkipped({String? placement, Map<String, Object>? properties}) =>
      track('paywall_skipped', _with('placement', placement, properties));

  /// An account was created.
  static Future<void> signUp({String? method, Map<String, Object>? properties}) =>
      track('sign_up', _with('method', method, properties));

  /// Someone signed in to an account they already had (a returning user). Not for new accounts: those are signUp.
  static Future<void> signIn({String? method, Map<String, Object>? properties}) =>
      track('sign_in', _with('method', method, properties));

  /// A free trial started. Not needed when RevenueCat is connected to Unolink.
  static Future<void> trialStarted({String? productId, Map<String, Object>? properties}) =>
      track('trial_started', _with('product_id', productId, properties));

  /// A purchase with its price, e.g. purchase('49.99', 'USD'). Pass the amount as a string so it's never rounded.
  /// Not needed when RevenueCat is connected to Unolink (it reports purchases, renewals and refunds itself).
  static Future<void> purchase(String amount, String currency, {String? productId, Map<String, Object>? properties}) =>
      _invoke('purchase', {'amount': amount, 'currency': currency, 'productId': productId, 'properties': properties});

  /// The user closed the store's purchase sheet without paying.
  static Future<void> purchaseCancelled({String? productId, Map<String, Object>? properties}) =>
      track('purchase_cancelled', _with('product_id', productId, properties));

  /// The purchase failed. reason is your own short description.
  static Future<void> purchaseFailed({String? productId, String? reason, Map<String, Object>? properties}) =>
      track('purchase_failed', _with('reason', reason, _with('product_id', productId, properties)));

  /// Your app's user ID, e.g. the ID you pass to RevenueCat's Purchases.logIn, so RevenueCat purchases join this
  /// install. Unolink stores only a keyed hash of it. Pass null on sign-out.
  static Future<void> setUserId(String? userId) => _invoke('setUserId', {'userId': userId});

  /// The random ID of this install (null before configure). It identifies no person or device.
  static Future<String?> getInstallId() async {
    try {
      return await _channel.invokeMethod<String>('getInstallId');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Sends queued events now. Normally not needed.
  static Future<void> flush() => _invoke('flush');

  /// Turns tracking off (queued events are deleted) or back on. Remembered across launches.
  static Future<void> setEnabled(bool enabled) => _invoke('setEnabled', {'enabled': enabled});

  /// Called once per install when it came from a Unolink link: open link.deepLink. Delivered even if set late.
  static void setDeferredDeepLinkListener(void Function(UnolinkDeepLink link)? listener) {
    _deepLinkListener = listener;
    final pending = _pendingDeepLink;
    if (listener != null && pending != null) {
      _pendingDeepLink = null;
      listener(pending);
    }
  }

  /// The server accepts only step, index and flow on onboarding events.
  static Map<String, Object> _onboarding(String step, int? index, String? flow) =>
      {'step': step, if (index != null) 'index': index, if (flow != null) 'flow': flow};

  static Map<String, Object>? _with(String key, String? value, Map<String, Object>? properties) =>
      value == null ? properties : {...?properties, key: value};

  static Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Web, desktop or tests without the native SDK: Unolink does nothing there.
    } on PlatformException {
      // The native SDK never throws; ignore anything unexpected rather than crash the app.
    }
  }
}
