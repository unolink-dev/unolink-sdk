import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unolink/unolink.dart';

/// onboardingStep / onboardingSkipped reach the native SDK as `track` with only step, index and flow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.unolink/sdk');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  test('onboardingStep carries step, index and flow', () async {
    await Unolink.onboardingStep('goal', index: 1, flow: 'v2');
    expect(calls.single.method, 'track');
    expect(calls.single.arguments, {
      'name': 'onboarding_step',
      'properties': {'step': 'goal', 'index': 1, 'flow': 'v2'},
    });
  });

  test('missing index and flow are left out', () async {
    await Unolink.onboardingStep('goal');
    expect(calls.single.arguments, {
      'name': 'onboarding_step',
      'properties': {'step': 'goal'},
    });
  });

  test('onboardingSkipped has the same shape', () async {
    await Unolink.onboardingSkipped('notifications', index: 3);
    expect(calls.single.arguments, {
      'name': 'onboarding_skipped',
      'properties': {'step': 'notifications', 'index': 3},
    });
  });

  test('without the native SDK it does nothing instead of throwing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await Unolink.onboardingStep('goal');
  });
}
