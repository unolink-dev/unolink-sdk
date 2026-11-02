import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unolink/unolink.dart';

/// The pending deferred deep link: Android's native SDK keeps it on disk until consumed (so it survives an app
/// restart); a link delivered this launch is also kept in Dart, for iPhone and older native builds.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.unolink/sdk');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  const link = {
    'deepLink': '/promo',
    'params': {'offer': '3for2'},
    'linkSlug': 'tiktok',
    'clickId': 'clk_1',
  };

  /// What the Android SDK keeps on disk (null: nothing, or the platform doesn't keep links).
  Map<String, Object?>? kept;

  /// The native SDK delivering the link to the plugin's listener.
  Future<void> emit(Map<String, Object?> link) => messenger.handlePlatformMessage(
      channel.name, const StandardMethodCodec().encodeMethodCall(MethodCall('onDeferredDeepLink', link)), (_) {});

  setUp(() async {
    calls.clear();
    kept = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getPendingDeferredDeepLink':
          return kept;
        case 'consumeDeferredDeepLink':
          kept = null;
      }
      return null;
    });
    await Unolink.configure('ulk_test');
    await Unolink.consumeDeferredDeepLink(); // a clean slate between tests
    Unolink.setDeferredDeepLinkListener(null);
    calls.clear();
  });

  test('a link kept from an earlier launch is pending without calling the listener', () async {
    kept = link;
    var heard = 0;
    Unolink.setDeferredDeepLinkListener((_) => heard++);
    final pending = await Unolink.getPendingDeferredDeepLink();
    expect(pending?.deepLink, '/promo');
    expect(pending?.params, {'offer': '3for2'});
    expect(pending?.linkSlug, 'tiktok');
    expect(pending?.clickId, 'clk_1');
    expect(heard, 0);
  });

  test('consume forgets it, natively too', () async {
    kept = link;
    await Unolink.consumeDeferredDeepLink();
    expect(calls.map((c) => c.method), contains('consumeDeferredDeepLink'));
    expect(await Unolink.getPendingDeferredDeepLink(), isNull);
  });

  test('a link delivered this launch stays pending until consumed (iPhone, older native builds)', () async {
    await emit(link); // nothing kept natively
    expect((await Unolink.getPendingDeferredDeepLink())?.deepLink, '/promo');
    await Unolink.consumeDeferredDeepLink();
    expect(await Unolink.getPendingDeferredDeepLink(), isNull);
  });

  test('a link that arrives before any listener goes to the first one set, once', () async {
    await emit(link);
    final heard = <UnolinkDeepLink>[];
    Unolink.setDeferredDeepLinkListener(heard.add);
    Unolink.setDeferredDeepLinkListener(heard.add);
    expect(heard.single.clickId, 'clk_1');
  });

  test('without the native SDK there is nothing pending and consume does nothing', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await Unolink.getPendingDeferredDeepLink(), isNull);
    await Unolink.consumeDeferredDeepLink();
  });
}
