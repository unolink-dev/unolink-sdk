import 'package:flutter/material.dart';
import 'package:unolink/unolink.dart';

// Run with your SDK key (never committed):
//   flutter run --dart-define=UNOLINK_KEY=ulk_…
// --dart-define=UNOLINK_AUTO_RUN=true fires every button's event once (automated end-to-end runs).
const _key = String.fromEnvironment('UNOLINK_KEY');
const _autoRun = bool.fromEnvironment('UNOLINK_AUTO_RUN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Unolink.configure(_key, baseUrl: 'https://api-uat.unolink.dev', logLevel: UnolinkLogLevel.debug, debug: true); // the sample is always a test device
  if (_autoRun) await _fireAll();
  runApp(const SampleApp());
}

Future<void> _fireAll() async {
  await Unolink.onboardingStep('goal', index: 0);
  await Unolink.onboardingStep('plan', index: 1);
  await Unolink.onboardingSkipped('notifications', index: 2);
  await Unolink.onboardingCompleted({'steps': 4});
  await Unolink.paywallViewed(placement: 'onboarding');
  await Unolink.paywallSkipped(placement: 'onboarding');
  await Unolink.setUserId('flutter-sample-user');
  await Unolink.signUp(method: 'email');
  await Unolink.signIn(method: 'email');
  await Unolink.trialStarted(productId: 'pro_yearly');
  await Unolink.purchase('4.99', 'USD', productId: 'pro_monthly');
  await Unolink.purchaseCancelled(productId: 'pro_monthly');
  await Unolink.track('level_up', {'level': 3});
  await Unolink.flush();
}

class SampleApp extends StatefulWidget {
  const SampleApp({super.key});

  @override
  State<SampleApp> createState() => _SampleAppState();
}

class _SampleAppState extends State<SampleApp> {
  String? _installId;
  String _deepLink = 'none (expected on iPhone)';
  String _note = '';

  @override
  void initState() {
    super.initState();
    Unolink.getInstallId().then((id) => setState(() => _installId = id));
    Unolink.setDeferredDeepLinkListener((link) => setState(() => _deepLink = '${link.deepLink} ${link.params} via /${link.linkSlug ?? ''}'));
  }

  Widget _button(String label, Future<void> Function() action) => ListTile(
        title: Text(label, style: const TextStyle(color: Colors.blue)),
        onTap: () async {
          await action();
          setState(() => _note = 'Sent: $label');
        },
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unolink Flutter sample',
      home: Scaffold(
        appBar: AppBar(title: const Text('Unolink sample (Flutter)')),
        body: ListView(children: [
          ListTile(title: const Text('API: api-uat.unolink.dev'), subtitle: Text(_key.isEmpty ? 'Key missing: --dart-define=UNOLINK_KEY=…' : 'Key: ${_key.substring(0, 12)}…')),
          ListTile(title: const Text('Install ID'), subtitle: Text(_installId ?? '…')),
          ListTile(title: const Text('Deferred deep link'), subtitle: Text(_deepLink)),
          if (_note.isNotEmpty) ListTile(subtitle: Text(_note)),
          const Divider(),
          _button('Onboarding screen: goal (0)', () => Unolink.onboardingStep('goal', index: 0)),
          _button('Onboarding screen: plan (1)', () => Unolink.onboardingStep('plan', index: 1)),
          _button('Skip onboarding screen: notifications (2)', () => Unolink.onboardingSkipped('notifications', index: 2)),
          _button('Onboarding completed', () => Unolink.onboardingCompleted({'steps': 4})),
          _button('Paywall viewed (onboarding)', () => Unolink.paywallViewed(placement: 'onboarding')),
          _button('Paywall skipped', () => Unolink.paywallSkipped(placement: 'onboarding')),
          _button('Sign up (set user ID)', () async {
            await Unolink.setUserId('flutter-sample-user');
            await Unolink.signUp(method: 'email');
          }),
          _button('Sign in (returning user)', () async {
            await Unolink.setUserId('flutter-sample-user');
            await Unolink.signIn(method: 'email');
          }),
          _button('Trial started', () => Unolink.trialStarted(productId: 'pro_yearly')),
          _button('Purchase 4.99 USD', () => Unolink.purchase('4.99', 'USD', productId: 'pro_monthly')),
          _button('Purchase cancelled', () => Unolink.purchaseCancelled(productId: 'pro_monthly')),
          _button('Custom event: level_up', () => Unolink.track('level_up', {'level': 3})),
          _button('Send now (flush)', Unolink.flush),
        ]),
      ),
    );
  }
}
