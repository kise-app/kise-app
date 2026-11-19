/// Widget tests for the second round of core features: expense search, filters and paging;
/// category management with limits; the account section (currency, password); profile sync;
/// and the Fixed tab's payment date and end month.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kise/features/categories/presentation/categories_screen.dart';
import 'package:kise/features/expenses/presentation/expenses_screen.dart';
import 'package:kise/features/fixed_expenses/presentation/fixed_expenses_screen.dart';
import 'package:kise/features/settings/presentation/settings_screen.dart';
import 'package:kise/platform/api/api.dart';
import 'package:kise/platform/session/profile_sync.dart';
import 'package:kise/platform/settings.dart';
import 'package:kise/platform/theme.dart';
import 'package:kise/shared_kernel/period.dart';

import '../support/fake_api.dart';

final _today = DateTime.utc(2026, 9, 4); // ነሐሴ 29, 2018

Widget _host(
  Widget child, {
  List<Override> overrides = const [],
  AppSettings settings = const AppSettings(language: Language.english),
}) => ProviderScope(
  overrides: [
    todayProvider.overrideWithValue(_today),
    settingsStoreProvider.overrideWithValue(InMemorySettingsStore(settings)),
    ...overrides,
  ],
  child: MaterialApp(theme: buildTheme(), home: child),
);

ExpensePageDto _page(int from, int count, int total) => ExpensePageDto.fromJson({
  'items': [
    for (var i = from; i < from + count; i++)
      {
        'id': 'e$i',
        'category_id': 'cat-1',
        'amount': {'amount_minor': 1000, 'currency': 'ETB'},
        'spent_on': {
          'gregorian': '2026-09-04',
          'ethiopian': '2018-12-29',
          'ethiopian_month_name_am': 'ነሐሴ',
          'ethiopian_month_name_en': 'Nehase',
          'entered_in': 'gregorian',
        },
        'note': 'row $i',
        'payment_method': 'cash',
        'category_name': 'Taxi',
        'category_name_am': null,
        'item': null,
      },
  ],
  'total': total,
  'limit': 50,
  'offset': from,
  'total_amount': {'amount_minor': total * 1000, 'currency': 'ETB'},
});

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

  group('expense search, filters and paging', () {
    testWidgets('search waits for a pause in typing, then asks the server', (tester) async {
      final expenses = FakeExpensesApi(page: pageOf([expenseRow(id: 'e1', amountMinor: 500)]));
      await tester.pumpWidget(
        _host(const ExpensesScreen(), overrides: fakeApiOverrides(expenses: expenses)),
      );
      await tester.pumpAndSettle();
      final before = expenses.listCalls.length;

      await tester.enterText(find.byKey(const Key('expenses-search')), 'sug');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byKey(const Key('expenses-search')), 'sugar');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final searches = expenses.listCalls.skip(before).map((c) => c['search']).toList();
      expect(searches, ['sugar'], reason: 'one request for the settled text, none for "sug"');
    });

    testWidgets('filters by category and payment method, shown as removable chips', (tester) async {
      final expenses = FakeExpensesApi(page: pageOf([expenseRow(id: 'e1', amountMinor: 500)]));
      await tester.pumpWidget(
        _host(
          const ExpensesScreen(),
          overrides: fakeApiOverrides(
            expenses: expenses,
            categories: FakeCategoriesApi([category('c1', 'Taxi'), category('c2', 'Food')]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('expenses-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-category-c2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-payment-telebirr')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-done')));
      await tester.pumpAndSettle();

      expect(expenses.listCalls.last['category_ids'], ['c2']);
      expect(expenses.listCalls.last['payment_methods'], ['telebirr']);
      expect(find.byKey(const Key('active-filter-c2')), findsOneWidget);

      // Removing the chip drops that filter.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('active-filter-c2')),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(expenses.listCalls.last['category_ids'], isEmpty);
      expect(expenses.listCalls.last['payment_methods'], ['telebirr']);
    });

    testWidgets('nothing matching offers to clear the filter', (tester) async {
      final expenses = FakeExpensesApi();
      await tester.pumpWidget(
        _host(const ExpensesScreen(), overrides: fakeApiOverrides(expenses: expenses)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('expenses-search')), 'nothing');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expenses-no-match')), findsOneWidget);
      await tester.tap(find.byKey(const Key('expenses-clear-filters')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expenses-empty')), findsOneWidget);
    });

    testWidgets('scrolling to the end loads the next page', (tester) async {
      final expenses = FakeExpensesApi()
        ..pager = (offset, limit) => _page(offset, offset == 0 ? 50 : 10, 60);
      await tester.pumpWidget(
        _host(const ExpensesScreen(), overrides: fakeApiOverrides(expenses: expenses)),
      );
      await tester.pumpAndSettle();
      expect(find.text('60 expenses'), findsOneWidget);
      expect(find.text('600.00 ETB'), findsOneWidget, reason: 'the total covers every page');

      // Scrolling toward the end of the first 50 fetches the next page, which holds e50..e59.
      await tester.scrollUntilVisible(
        find.byKey(const Key('expense-tile-e59')),
        600,
        scrollable: find.descendant(
          of: find.byKey(const Key('expenses-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(expenses.listCalls.map((c) => c['offset']).toList(), [0, 50]);
      expect(find.byKey(const Key('expenses-loading-more')), findsNothing);
    });
  });

  group('categories', () {
    testWidgets('a new category is created with its colour, icon and monthly limit', (
      tester,
    ) async {
      final categories = FakeCategoriesApi();
      final budgets = FakeBudgetsApi();
      await tester.pumpWidget(
        _host(
          const CategoriesScreen(),
          overrides: fakeApiOverrides(categories: categories, budgets: budgets),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('category-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('category-name')), 'Gifts');
      await tester.enterText(find.byKey(const Key('category-name-am')), 'ስጦታ');
      await tester.tap(find.byKey(const Key('category-color-#8E24AA')));
      await tester.tap(find.byKey(const Key('category-icon-celebration')));
      await tester.enterText(find.byKey(const Key('category-budget')), '1500');
      await tester.tap(find.byKey(const Key('category-save')));
      await tester.pumpAndSettle();

      expect(categories.calls, ['create:Gifts:ስጦታ:#8E24AA:celebration']);
      expect(budgets.calls, ['set:cat-new-0:150000']);
      expect(find.text('Gifts'), findsOneWidget);
      expect(find.textContaining('Limit 1,500 ETB'), findsOneWidget);
    });

    testWidgets('editing sends only what changed, and clearing the limit removes it', (
      tester,
    ) async {
      final categories = FakeCategoriesApi([category('c1', 'Food', color: '#E53935')]);
      final budgets = FakeBudgetsApi({'c1': 500000});
      await tester.pumpWidget(
        _host(
          const CategoriesScreen(),
          overrides: fakeApiOverrides(categories: categories, budgets: budgets),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('category-c1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('category-name')), 'Groceries');
      await tester.enterText(find.byKey(const Key('category-budget')), '');
      await tester.tap(find.byKey(const Key('category-save')));
      await tester.pumpAndSettle();

      expect(categories.calls, ['update:c1:Groceries:-:-:-']);
      expect(budgets.calls, ['clear:c1']);
    });

    testWidgets('deleting a category in use archives it, and it can be restored', (tester) async {
      final categories = FakeCategoriesApi([category('c1', 'Clothing')], {'c1'});
      await tester.pumpWidget(
        _host(const CategoriesScreen(), overrides: fakeApiOverrides(categories: categories)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('category-c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();

      expect(find.text('Archived, because expenses use it'), findsOneWidget);
      await tester.tap(find.byKey(const Key('categories-show-archived')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category-restore-c1')));
      await tester.pumpAndSettle();
      expect(categories.calls, ['remove:c1', 'restore:c1']);
      expect(find.byKey(const Key('categories-show-archived')), findsNothing);
    });
  });

  group('account', () {
    testWidgets('the currency is shown, not chosen', (tester) async {
      await tester.pumpWidget(
        _host(
          const SettingsScreen(),
          overrides: fakeApiOverrides(),
          settings: const AppSettings(language: Language.english, currency: 'USD'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('account-currency'))).data, 'USD');
      expect(find.text('ETB'), findsNothing);
    });

    testWidgets('changing the password checks the confirmation, then calls the server', (
      tester,
    ) async {
      final auth = FakeAuthApi();
      await tester.pumpWidget(
        _host(const SettingsScreen(), overrides: fakeApiOverrides(auth: auth)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('change-password')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('password-current')), 'old password');
      await tester.enterText(find.byKey(const Key('password-new')), 'new password 1');
      await tester.enterText(find.byKey(const Key('password-confirm')), 'typo');
      await tester.tap(find.byKey(const Key('password-submit')));
      await tester.pumpAndSettle();
      expect(find.text('The passwords do not match'), findsOneWidget);
      expect(auth.passwordChanges, isEmpty);

      await tester.enterText(find.byKey(const Key('password-confirm')), 'new password 1');
      await tester.tap(find.byKey(const Key('password-submit')));
      await tester.pumpAndSettle();
      expect(auth.passwordChanges, [
        {'current': 'old password', 'new': 'new password 1'},
      ]);
      expect(find.text('Password changed'), findsOneWidget);
    });

    testWidgets('a wrong current password is shown on that field', (tester) async {
      final auth = FakeAuthApi(
        passwordError: const ApiException(
          message: 'The current password is incorrect',
          code: 'current_password_incorrect',
          statusCode: 422,
        ),
      );
      await tester.pumpWidget(
        _host(const SettingsScreen(), overrides: fakeApiOverrides(auth: auth)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('change-password')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('password-current')), 'wrong one');
      await tester.enterText(find.byKey(const Key('password-new')), 'new password 1');
      await tester.enterText(find.byKey(const Key('password-confirm')), 'new password 1');
      await tester.tap(find.byKey(const Key('password-submit')));
      await tester.pumpAndSettle();
      expect(find.text('That is not your current password'), findsOneWidget);
    });
  });

  group('profile sync', () {
    test('applying a profile updates settings without pushing it back', () async {
      final auth = FakeAuthApi();
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          authApiProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(profileSyncProvider)
          .apply(
            profile(displayName: 'Selam', calendar: 'gregorian', language: 'en', currency: 'USD'),
          );
      await Future<void>.delayed(Duration.zero);

      final settings = container.read(settingsProvider);
      expect(settings.ownerName, 'Selam');
      expect(settings.calendar, CalendarKind.gregorian);
      expect(settings.language, Language.english);
      expect(settings.currency, 'USD');
      expect(auth.updates, isEmpty);
    });

    test('calendar and language changes are pushed at once, the name after a pause', () async {
      final auth = FakeAuthApi();
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          authApiProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);
      container.read(profileSyncProvider).apply(profile(displayName: 'Test'));
      final controller = container.read(settingsProvider.notifier);

      controller.setLanguage(Language.english);
      await Future<void>.delayed(Duration.zero);
      expect(auth.updates.single, {
        'display_name': null,
        'calendar': 'ethiopian',
        'language': 'en',
      });

      controller.setOwnerName('Se');
      controller.setOwnerName('Selam');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(auth.updates, hasLength(1), reason: 'still typing');
      await Future<void>.delayed(ProfileSync.nameDebounce);
      expect(auth.updates, hasLength(2));
      expect(auth.updates.last['display_name'], 'Selam');
    });

    test('nothing is pushed before a profile is applied (signed out)', () async {
      final auth = FakeAuthApi();
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          authApiProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);
      container.read(profileSyncProvider);
      container.read(settingsProvider.notifier).setCalendar(CalendarKind.gregorian);
      await Future<void>.delayed(Duration.zero);
      expect(auth.updates, isEmpty);
    });
  });

  group('fixed expenses', () {
    testWidgets('marking paid can record an earlier payment date', (tester) async {
      final api = FakeFixedExpensesApi([fixedExpense('fx-1', 'Rent', 800000)]);
      await tester.pumpWidget(
        _host(const FixedExpensesScreen(), overrides: fakeApiOverrides(fixedExpenses: api)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settle-fx-1')));
      await tester.pumpAndSettle();
      expect(find.text('Nehase 29, 2018'), findsOneWidget, reason: 'defaults to today');

      await tester.tap(find.byKey(const Key('settle-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settle-confirm')));
      await tester.pumpAndSettle();

      expect(api.lastSettledOn, '2026-09-01');
    });

    testWidgets('a commitment can be given a last month', (tester) async {
      final api = FakeFixedExpensesApi();
      await tester.pumpWidget(
        _host(
          const FixedExpensesScreen(),
          overrides: fakeApiOverrides(
            fixedExpenses: api,
            categories: FakeCategoriesApi([category('c-rent', 'Rent')]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fixed-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('fixed-title')), 'Lease');
      await tester.enterText(find.byKey(const Key('fixed-amount')), '8000');
      await tester.tap(find.byKey(const Key('fixed-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rent').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fixed-has-end')));
      await tester.pumpAndSettle();
      // ነሐሴ 2018 + 12 months = ሐምሌ 2019 (ጳጉሜን counts as a month).
      expect(tester.widget<Text>(find.byKey(const Key('fixed-end-label'))).data, 'Hamle 2019');
      await tester.tap(find.byKey(const Key('fixed-end-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fixed-submit')));
      await tester.pumpAndSettle();

      expect(api.lastSchedule!['end_period'], Period(CalendarKind.ethiopian, 2019, 12));
    });

    testWidgets('switching the end off on an edit clears it', (tester) async {
      final api = FakeFixedExpensesApi([
        FixedExpenseDto.fromJson({
          'id': 'fx-1',
          'category_id': 'c-rent',
          'category_name': 'Rent',
          'category_name_am': null,
          'title': 'Lease',
          'amount': {'amount_minor': 800000, 'currency': 'ETB'},
          'anchor_calendar': 'ethiopian',
          'start_period': {'year': 2018, 'month': 12, 'calendar': 'ethiopian'},
          'end_period': {'year': 2019, 'month': 11, 'calendar': 'ethiopian'},
          'due_day': 5,
          'note': null,
          'is_paused': false,
          'settled_periods': <Object?>[],
        }),
      ]);
      await tester.pumpWidget(
        _host(
          const FixedExpensesScreen(),
          overrides: fakeApiOverrides(
            fixedExpenses: api,
            categories: FakeCategoriesApi([category('c-rent', 'Rent')]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('occurrence-fx-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fixed-action-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fixed-has-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fixed-submit')));
      await tester.pumpAndSettle();

      expect(api.lastUpdate, {'end_period': null, 'clear_end_period': true});
    });
  });
}
