import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unolink/unolink.dart';

/// Stands in for purchases_flutter's CustomerInfo and its listener functions, to show their real signatures fit.
class FakeCustomerInfo {}

final _listeners = <void Function(FakeCustomerInfo)>[];
void addCustomerInfoUpdateListener(void Function(FakeCustomerInfo) listener) => _listeners.add(listener);
void removeCustomerInfoUpdateListener(void Function(FakeCustomerInfo) listener) => _listeners.remove(listener);
void emitCustomerInfo() {
  for (final l in [..._listeners]) {
    l(FakeCustomerInfo());
  }
}

/// connectRevenueCat reports RevenueCat's app user ID through setUserId, only when it changed. Its own file: the
/// first test needs Unolink not configured yet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.unolink/sdk');
  final userIds = <Object?>[];
  String? current;
  Object? failure;

  Future<String?> appUserId() async {
    if (failure != null) throw failure!;
    return current;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    userIds.clear();
    current = r'$RCAnonymousID:guest';
    failure = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setUserId') userIds.add((call.arguments as Map)['userId']);
      return null;
    });
  });

  test('connected before configure: reported once configure has run', () async {
    final disconnect = Unolink.connectRevenueCat(appUserId);
    await settle();
    expect(userIds, isEmpty);
    await Unolink.configure('ulk_test');
    await settle();
    expect(userIds, [r'$RCAnonymousID:guest']);
    disconnect();
  });

  test('customer info updates report a changed ID, once', () async {
    final disconnect = Unolink.connectRevenueCat(appUserId,
        addListener: addCustomerInfoUpdateListener, removeListener: removeCustomerInfoUpdateListener);
    await settle();
    expect(userIds, [r'$RCAnonymousID:guest']);
    emitCustomerInfo(); // same ID
    await settle();
    expect(userIds, [r'$RCAnonymousID:guest']);
    current = 'account-42'; // Purchases.logIn
    emitCustomerInfo();
    await settle();
    expect(userIds, [r'$RCAnonymousID:guest', 'account-42']);

    disconnect();
    expect(_listeners, isEmpty);
    current = 'account-7';
    emitCustomerInfo();
    await settle();
    expect(userIds, [r'$RCAnonymousID:guest', 'account-42']);
  });

  test('errors and unknown IDs are skipped, and read again later', () async {
    failure = PlatformException(code: 'not_configured');
    final disconnect = Unolink.connectRevenueCat(appUserId);
    await settle();
    expect(userIds, isEmpty);
    failure = null;
    current = null;
    await Unolink.revenueCatUserChanged();
    expect(userIds, isEmpty);
    current = 'account-42';
    await Unolink.revenueCatUserChanged();
    expect(userIds, ['account-42']);
    disconnect();
  });

  test('the app resuming reads the ID again', () async {
    final binding = TestWidgetsFlutterBinding.instance;
    final disconnect = Unolink.connectRevenueCat(appUserId);
    await settle();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    current = r'$RCAnonymousID:after-logout';
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle();
    expect(userIds, [r'$RCAnonymousID:guest', r'$RCAnonymousID:after-logout']);
    disconnect();
  });
}
