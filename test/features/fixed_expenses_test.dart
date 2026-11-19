/// Widget tests for the Fixed tab: commitments owed this month, marking them paid, and managing
/// them (schedule, edit, pause, delete). The API is an in-memory fake, so the screen is driven
/// end to end the way a person would use it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kise/features/fixed_expenses/presentation/fixed_expenses_screen.dart';
import 'package:kise/platform/settings.dart';
import 'package:kise/platform/theme.dart';
import 'package:kise/shared_kernel/period.dart';

import '../support/fake_api.dart';

/// 4 September 2026 is ነሐሴ 29, 2018.
final _today = DateTime.utc(2026, 9, 4);

Widget _host(FakeFixedExpensesApi api) => ProviderScope(
      overrides: [
        todayProvider.overrideWithValue(_today),
        settingsStoreProvider.overrideWithValue(
          InMemorySettingsStore(const AppSettings(language: Language.english)),
        ),
        ...fakeApiOverrides(
          fixedExpenses: api,
          categories: FakeCategoriesApi([category('c-rent', 'Rent')]),
        ),
      ],
      child: MaterialApp(theme: buildTheme(), home: const FixedExpensesScreen()),
    );

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 2600);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('with no commitments it explains what the tab is for', (tester) async {
    await tester.pumpWidget(_host(FakeFixedExpensesApi()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fixed-empty')), findsOneWidget);
    expect(find.textContaining('rent, internet'), findsOneWidget);
  });

  testWidgets('lists what is owed this month with the totals', (tester) async {
    await tester.pumpWidget(_host(FakeFixedExpensesApi([
      fixedExpense('fx-1', 'Rent', 800000),
      fixedExpense('fx-2', 'Internet', 20000),
    ])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('occurrence-fx-1')), findsOneWidget);
    expect(find.byKey(const Key('occurrence-fx-2')), findsOneWidget);
    expect(_text(tester, 'fixed-total-committed'), '8,200 ETB');
    expect(_text(tester, 'fixed-total-outstanding'), '8,200 ETB');
    expect(find.textContaining('Due Nehase 5'), findsNWidgets(2));
  });

  testWidgets('the circle marks it paid with the amount actually paid', (tester) async {
    final api = FakeFixedExpensesApi([fixedExpense('fx-1', 'Electricity', 50000)]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settle-fx-1')));
    await tester.pumpAndSettle();
    // Pre-filled with the committed amount; the bill came in lower.
    expect(find.widgetWithText(TextField, '500'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('settle-amount')), '430');
    await tester.tap(find.byKey(const Key('settle-confirm')));
    await tester.pumpAndSettle();

    expect(api.calls, ['settle:fx-1:43000']);
    expect(_text(tester, 'fixed-total-settled'), '430 ETB');
    expect(_text(tester, 'fixed-total-outstanding'), '0 ETB');
    expect(find.textContaining('Paid Nehase 4'), findsOneWidget);

    // Tapping again undoes it.
    await tester.tap(find.byKey(const Key('settle-fx-1')));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'unsettle:fx-1');
    expect(_text(tester, 'fixed-total-outstanding'), '500 ETB');
  });

  testWidgets('settling for the committed amount does not send an override', (tester) async {
    final api = FakeFixedExpensesApi([fixedExpense('fx-1', 'Rent', 800000)]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settle-fx-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settle-confirm')));
    await tester.pumpAndSettle();

    expect(api.calls, ['settle:fx-1:committed']);
  });

  testWidgets('a new commitment starts in the month being viewed', (tester) async {
    final api = FakeFixedExpensesApi();
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fixed-add')));
    await tester.pumpAndSettle();
    expect(find.text('Every month from Nehase 2018'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('fixed-title')), 'Rent');
    await tester.enterText(find.byKey(const Key('fixed-amount')), '8000');
    await tester.tap(find.byKey(const Key('fixed-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rent').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fixed-due-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fixed-submit')));
    await tester.pumpAndSettle();

    expect(api.lastSchedule!['title'], 'Rent');
    expect(api.lastSchedule!['amount_minor'], 800000);
    expect(api.lastSchedule!['category_id'], 'c-rent');
    expect(api.lastSchedule!['due_day'], 5);
    expect(api.lastSchedule!['start_period'], Period(CalendarKind.ethiopian, 2018, 12));
    // The list refreshed and shows it.
    expect(find.byKey(const Key('occurrence-fx-1')), findsOneWidget);
  });

  testWidgets('pausing moves it out of this month; it can be resumed from below', (tester) async {
    final api = FakeFixedExpensesApi([fixedExpense('fx-1', 'Gym', 150000)]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('occurrence-fx-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fixed-action-pause')));
    await tester.pumpAndSettle();

    expect(api.calls, ['pause:fx-1']);
    expect(find.byKey(const Key('occurrence-fx-1')), findsNothing);
    expect(find.byKey(const Key('commitment-fx-1')), findsOneWidget);
    expect(find.text('Paused'), findsWidgets);

    await tester.tap(find.byKey(const Key('commitment-fx-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fixed-action-resume')));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'resume:fx-1');
    expect(find.byKey(const Key('occurrence-fx-1')), findsOneWidget);
  });

  testWidgets('delete asks first, then removes it', (tester) async {
    final api = FakeFixedExpensesApi([fixedExpense('fx-1', 'Rent', 800000)]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('occurrence-fx-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fixed-action-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete Rent?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();

    expect(api.calls, ['delete:fx-1']);
    expect(find.byKey(const Key('fixed-empty')), findsOneWidget);
  });

  testWidgets('edit opens the form pre-filled and saves changes', (tester) async {
    final api = FakeFixedExpensesApi([fixedExpense('fx-1', 'Rent', 800000)]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('occurrence-fx-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fixed-action-edit')));
    await tester.pumpAndSettle();

    expect(find.text('Edit fixed expense'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('fixed-amount')), '9000');
    await tester.tap(find.byKey(const Key('fixed-submit')));
    await tester.pumpAndSettle();

    expect(api.calls, ['update:fx-1']);
    expect(_text(tester, 'fixed-total-committed'), '9,000 ETB');
  });
}
