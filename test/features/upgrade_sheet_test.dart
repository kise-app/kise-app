/// The upgrade sheet: how to pay for Pro by hand, as set in the admin portal.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kise/features/plans/upgrade_sheet.dart';
import 'package:kise/platform/links.dart';
import 'package:kise/platform/settings.dart';
import 'package:kise/platform/theme.dart';
import 'package:kise/shared_kernel/period.dart';

import '../support/fake_api.dart';

Widget _host(FakePlansApi plans, {List<Uri>? opened, bool opens = true}) => ProviderScope(
  overrides: [
    settingsStoreProvider.overrideWithValue(
      InMemorySettingsStore(const AppSettings(language: Language.english)),
    ),
    ...fakeApiOverrides(plans: plans),
    linkOpenerProvider.overrideWithValue((uri) async {
      opened?.add(uri);
      return opens;
    }),
  ],
  child: MaterialApp(
    theme: buildTheme(),
    home: Consumer(
      builder: (context, ref, _) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('open'),
            onPressed: () => showUpgradeSheet(context, ref.read(settingsProvider)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

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

  testWidgets('until an admin sets payment details, it says to contact the team', (tester) async {
    await tester.pumpWidget(_host(FakePlansApi()));
    await _open(tester);
    expect(find.byKey(const Key('upgrade-contact-us')), findsOneWidget);
    expect(find.byKey(const Key('upgrade-how-to-pay')), findsNothing);
  });

  testWidgets('shows the price, the accounts and the email to quote', (tester) async {
    await tester.pumpWidget(_host(FakePlansApi(payment: fakePaymentInfo())));
    await _open(tester);
    expect(find.text('300 birr a month'), findsOneWidget);
    expect(find.text('Commercial Bank of Ethiopia'), findsOneWidget);
    expect(find.text('Kise PLC\n0911234567'), findsOneWidget);
    expect(find.textContaining('test@example.com', findRichText: true), findsOneWidget);
    expect(find.text('Once we have checked the payment, we switch you to Pro.'), findsOneWidget);
  });

  testWidgets('copies an account number', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_host(FakePlansApi(payment: fakePaymentInfo())));
    await _open(tester);
    await tester.tap(find.byKey(const Key('upgrade-copy-0')));
    await tester.pump();
    expect(copied, '1000123456789');
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('opens Telegram, the dialler and the mail app', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(_host(FakePlansApi(payment: fakePaymentInfo()), opened: opened));
    await _open(tester);
    for (final key in ['upgrade-telegram', 'upgrade-phone', 'upgrade-email']) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }
    expect(opened[0], Uri.parse('https://t.me/kise_support'));
    expect(opened[1], Uri(scheme: 'tel', path: '+251911234567'));
    expect(opened[2].scheme, 'mailto');
    expect(opened[2].path, 'pay@kise.example');
    expect(opened[2].queryParameters['body'], 'Kise account: test@example.com');
  });

  testWidgets('says so when a link cannot be opened', (tester) async {
    await tester.pumpWidget(_host(FakePlansApi(payment: fakePaymentInfo()), opens: false));
    await _open(tester);
    await tester.tap(find.byKey(const Key('upgrade-telegram')));
    await tester.pump();
    expect(find.text('Could not open that'), findsOneWidget);
  });

  testWidgets("the admin's note replaces the default line", (tester) async {
    await tester.pumpWidget(
      _host(FakePlansApi(payment: fakePaymentInfo(note: 'We switch you within a day.'))),
    );
    await _open(tester);
    expect(find.text('We switch you within a day.'), findsOneWidget);
  });
}
