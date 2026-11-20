/// The plan card in Settings: what the account is on, and what Basic is missing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kise/features/settings/presentation/settings_screen.dart';
import 'package:kise/platform/settings.dart';
import 'package:kise/platform/theme.dart';
import 'package:kise/shared_kernel/period.dart';

import '../support/fake_api.dart';

Widget _host(Map<String, Object?>? plan) => ProviderScope(
  overrides: [
    settingsStoreProvider.overrideWithValue(
      InMemorySettingsStore(const AppSettings(language: Language.english)),
    ),
    ...fakeApiOverrides(plan: plan),
  ],
  child: MaterialApp(theme: buildTheme(), home: const SettingsScreen()),
);

String _name(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('plan-name'))).data!;

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 3200);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('a running trial shows the days left', (tester) async {
    await tester.pumpWidget(
      _host({'plan': 'trial', 'effective': 'trial', 'days_left': 9, 'ai_enabled': true}),
    );
    await tester.pumpAndSettle();
    expect(_name(tester), 'Trial');
    expect(find.textContaining('9 days left'), findsOneWidget);
    // A trial can already see how to get Pro.
    await tester.tap(find.byKey(const Key('plan-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upgrade-sheet')), findsOneWidget);
  });

  testWidgets('Basic says what is missing and opens the Pro explanation', (tester) async {
    await tester.pumpWidget(
      _host({'plan': 'trial', 'effective': 'basic', 'days_left': null, 'ai_enabled': false}),
    );
    await tester.pumpAndSettle();
    expect(_name(tester), 'Basic');
    await tester.tap(find.byKey(const Key('plan-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upgrade-sheet')), findsOneWidget);
  });

  testWidgets('a plan an admin added shows its own name and can still upgrade', (tester) async {
    await tester.pumpWidget(
      _host({
        'plan': 'family',
        'effective': 'family',
        'name': 'Family',
        'days_left': 20,
        'ai_enabled': true,
        'receipts_per_month': 100,
        'voice_per_month': 40,
      }),
    );
    await tester.pumpAndSettle();
    expect(_name(tester), 'Family');
    expect(find.textContaining('20 days left'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plan-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upgrade-sheet')), findsOneWidget, reason: 'it has limits');
  });

  testWidgets('open-ended Pro', (tester) async {
    await tester.pumpWidget(_host({'plan': 'pro', 'effective': 'pro', 'ai_enabled': true}));
    await tester.pumpAndSettle();
    expect(_name(tester), 'Pro');
    expect(find.text('Everything, including the assistant'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plan-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upgrade-sheet')), findsNothing, reason: 'nothing to upgrade to');
  });
}
