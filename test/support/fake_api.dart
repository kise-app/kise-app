/// Test doubles for the API layer, so widget tests never touch the network.
///
/// Widget tests that pump the app (or the expenses screen) pull in providers that would otherwise
/// build a real Dio client and fire HTTP requests — leaving pending timers and failing the test.
/// These fakes return canned data synchronously, and [fakeApiOverrides] wires them into a
/// ProviderScope. A test that wants specific data passes its own instances.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kise/platform/api/api.dart';
import 'package:kise/platform/session/session_controller.dart';
import 'package:kise/shared_kernel/period.dart';

class FakeExpensesApi implements ExpensesApi {
  FakeExpensesApi({ExpensePageDto? page, this.onRecord}) : _page = page ?? emptyPage();

  ExpensePageDto _page;
  final Future<ExpenseDto> Function(Map<String, Object?> body)? onRecord;

  /// The last record() call's arguments, for assertions.
  Map<String, Object?>? lastRecord;

  /// The last update() call's id and arguments.
  Map<String, Object?>? lastUpdate;

  /// Ids passed to delete(), in order.
  final List<String> deleted = [];

  /// Every list() call's filter and paging arguments, in order.
  final List<Map<String, Object?>> listCalls = [];

  /// When set, list() answers from this instead of the fixed page — for paging tests.
  ExpensePageDto Function(int offset, int limit)? pager;

  static ExpensePageDto emptyPage() => ExpensePageDto.fromJson({
    'items': <Object?>[],
    'total': 0,
    'limit': 50,
    'offset': 0,
    'total_amount': {'amount_minor': 0, 'currency': 'ETB'},
  });

  void setPage(ExpensePageDto page) => _page = page;

  @override
  Future<ExpensePageDto> list({
    int? periodYear,
    int? periodMonth,
    String periodCalendar = 'ethiopian',
    String? since,
    String? until,
    String dateCalendar = 'gregorian',
    List<String> categoryIds = const [],
    List<String> paymentMethods = const [],
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    listCalls.add({
      'category_ids': categoryIds,
      'payment_methods': paymentMethods,
      'search': search,
      'limit': limit,
      'offset': offset,
    });
    if (pager != null) return pager!(offset, limit);
    return _page;
  }

  @override
  Future<ExpenseDto> record({
    required String categoryId,
    required int amountMinor,
    required String date,
    String dateCalendar = 'gregorian',
    String? note,
    String? paymentMethod,
    String? itemId,
    String? itemName,
    String? itemNameAm,
    String? quantity,
    String? unitId,
  }) async {
    lastRecord = {
      'category_id': categoryId,
      'amount_minor': amountMinor,
      'date': date,
      'note': note,
      'payment_method': paymentMethod,
      'item_name': itemName,
      'quantity': quantity,
      'unit_id': unitId,
    };
    if (onRecord != null) return onRecord!(lastRecord!);
    return _expense(categoryId: categoryId, amountMinor: amountMinor, date: date);
  }

  @override
  Future<ExpenseDto> get(String id) async => throw UnimplementedError();

  @override
  Future<ExpenseDto> update(
    String id, {
    String? categoryId,
    int? amountMinor,
    String? date,
    String dateCalendar = 'gregorian',
    String? note,
    String? paymentMethod,
    String? itemId,
    String? itemName,
    String? itemNameAm,
    String? quantity,
    String? unitId,
    bool clearItem = false,
  }) async {
    lastUpdate = {
      'id': id,
      'category_id': categoryId,
      'amount_minor': amountMinor,
      'date': date,
      'note': note,
      'payment_method': paymentMethod,
      'item_name': itemName,
      'quantity': quantity,
      'unit_id': unitId,
      'clear_item': clearItem,
    };
    return _expense(
      categoryId: categoryId ?? 'cat-1',
      amountMinor: amountMinor ?? 0,
      date: date ?? '2026-09-04',
    );
  }

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

/// A dashboard month. The default looks like a real month (rent + internet committed, ~1,246 ETB
/// of day-to-day spending) so layout assertions have something to bite on.
class FakeMonthlySummaryApi implements MonthlySummaryApi {
  FakeMonthlySummaryApi({this.build});

  final MonthlySummaryDto Function(Period period)? build;

  /// Every period asked for, in order.
  final List<Period> requested = [];

  @override
  Future<MonthlySummaryDto> forPeriod({
    required int year,
    required int month,
    String calendar = 'ethiopian',
  }) async {
    final period = Period(CalendarKind.parse(calendar), year, month);
    requested.add(period);
    return (build ?? defaultSummary)(period);
  }

  static MonthlySummaryDto defaultSummary(Period period) {
    final days = period.lengthInDays;
    final daily = List<int>.generate(days, (i) => i == 2 ? 30000 : (i % 3 == 0 ? 3000 : 0));
    final dynamicMinor = daily.fold<int>(0, (a, b) => a + b);
    return summaryOf(
      committedMinor: 820000,
      settledMinor: 800000,
      dynamicMinor: dynamicMinor,
      previousTotalMinor: 900000,
      expenseCount: 17,
      daily: daily,
      categories: [
        spend('c-rent', 'Rent', 'ቤት ኪራይ', '#6D4C41', 'home', committedMinor: 800000),
        spend('c-food', 'Food', 'ምግብ', '#E53935', 'restaurant', dynamicMinor: dynamicMinor),
        spend(
          'c-net',
          'Airtime & Internet',
          'ካርድና ኢንተርኔት',
          '#00897B',
          'wifi',
          committedMinor: 20000,
        ),
      ],
    );
  }
}

CategorySpendDto spend(
  String id,
  String name,
  String? nameAm,
  String color,
  String? icon, {
  int dynamicMinor = 0,
  int committedMinor = 0,
  int expenseCount = 1,
  int? budgetMinor,
}) => CategorySpendDto.fromJson({
  'budget': budgetMinor == null ? null : _m(budgetMinor),
  'category_id': id,
  'name': name,
  'name_am': nameAm,
  'color': color,
  'icon': icon,
  'total': _m(dynamicMinor + committedMinor),
  'dynamic': _m(dynamicMinor),
  'committed': _m(committedMinor),
  'expense_count': expenseCount,
});

MonthlySummaryDto summaryOf({
  required List<int> daily,
  int committedMinor = 0,
  int settledMinor = 0,
  int? dynamicMinor,
  int previousTotalMinor = 0,
  int expenseCount = 0,
  List<CategorySpendDto> categories = const [],
}) {
  final dynamicTotal = dynamicMinor ?? daily.fold<int>(0, (a, b) => a + b);
  return MonthlySummaryDto.fromJson({
    'currency': 'ETB',
    'grand_total': _m(dynamicTotal + committedMinor),
    'dynamic_total': _m(dynamicTotal),
    'expense_count': expenseCount,
    'committed': _m(committedMinor),
    'settled': _m(settledMinor),
    'outstanding': _m(committedMinor - settledMinor),
    'previous_total': _m(previousTotalMinor),
    'daily_minor': daily,
    'categories': [
      for (final c in categories)
        {
          'category_id': c.categoryId,
          'name': c.name,
          'name_am': c.nameAm,
          'color': c.color,
          'icon': c.icon,
          'total': _m(c.totalMinor),
          'dynamic': _m(c.dynamicMinor),
          'committed': _m(c.committedMinor),
          'expense_count': c.expenseCount,
          'budget': c.budgetMinor == null ? null : _m(c.budgetMinor!),
        },
    ],
  });
}

Map<String, Object?> _m(int minor) => {'amount_minor': minor, 'currency': 'ETB'};

class FakeItemUsageReportsApi implements ItemUsageReportsApi {
  @override
  Future<ItemUsageReportDto> forPeriod({
    required int year,
    required int month,
    String calendar = 'ethiopian',
  }) async => ItemUsageReportDto.fromJson({
    'period': {'calendar': calendar, 'label_am': '', 'label_en': ''},
    'currency': 'ETB',
    'lines': <Object?>[],
  });
}

/// An in-memory Fixed Monthly Expenses backend: commitments are owed in every month from their
/// start unless paused, and settling marks them paid for that month.
class FakeFixedExpensesApi implements FixedExpensesApi {
  FakeFixedExpensesApi([List<FixedExpenseDto> commitments = const []])
    : commitments = [...commitments];

  final List<FixedExpenseDto> commitments;

  /// fixedExpenseId -> amount paid, for the (single) month under test.
  final Map<String, int> settled = {};
  final List<String> calls = [];
  Map<String, Object?>? lastSchedule;
  Map<String, Object?>? lastUpdate;
  String? lastSettledOn;

  @override
  Future<List<FixedExpenseDto>> list() async => [...commitments];

  @override
  Future<OccurrenceMonthDto> occurrences(Period period) async {
    final owed = commitments.where((c) => !c.isPaused).toList();
    final rows = [
      for (final c in owed)
        {
          'fixed_expense_id': c.id,
          'category_id': c.categoryId,
          'category_name': c.categoryName,
          'category_name_am': c.categoryNameAm,
          'title': c.title,
          'period': periodToJson(period),
          'due_date': _date('2026-08-11', '2018-12-05'),
          'amount': _m(settled[c.id] ?? c.amount.minorUnits),
          'is_settled': settled.containsKey(c.id),
          'settled_on': settled.containsKey(c.id) ? _date('2026-08-10', '2018-12-04') : null,
        },
    ];
    final committed = rows.fold<int>(
      0,
      (sum, r) => sum + ((r['amount'] as Map)['amount_minor'] as int),
    );
    final paid = rows
        .where((r) => r['is_settled'] == true)
        .fold<int>(0, (sum, r) => sum + ((r['amount'] as Map)['amount_minor'] as int));
    return OccurrenceMonthDto.fromJson({
      'occurrences': rows,
      'committed': _m(committed),
      'settled': _m(paid),
      'outstanding': _m(committed - paid),
    });
  }

  @override
  Future<FixedExpenseDto> schedule({
    required String categoryId,
    required String title,
    required int amountMinor,
    required Period startPeriod,
    Period? endPeriod,
    int dueDay = 1,
    String? note,
  }) async {
    lastSchedule = {
      'category_id': categoryId,
      'title': title,
      'amount_minor': amountMinor,
      'start_period': startPeriod,
      'end_period': endPeriod,
      'due_day': dueDay,
      'note': note,
    };
    final created = fixedExpense(
      'fx-${commitments.length + 1}',
      title,
      amountMinor,
      categoryId: categoryId,
      dueDay: dueDay,
      start: startPeriod,
    );
    commitments.add(created);
    return created;
  }

  @override
  Future<FixedExpenseDto> update(
    String id, {
    String? title,
    int? amountMinor,
    String? categoryId,
    int? dueDay,
    String? note,
    Period? endPeriod,
    bool clearEndPeriod = false,
  }) async {
    calls.add('update:$id');
    lastUpdate = {'end_period': endPeriod, 'clear_end_period': clearEndPeriod};
    final index = commitments.indexWhere((c) => c.id == id);
    final old = commitments[index];
    commitments[index] = fixedExpense(
      id,
      title ?? old.title,
      amountMinor ?? old.amount.minorUnits,
      categoryId: categoryId ?? old.categoryId,
      dueDay: dueDay ?? old.dueDay,
    );
    return commitments[index];
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete:$id');
    commitments.removeWhere((c) => c.id == id);
  }

  FixedExpenseDto _setPaused(String id, bool paused) {
    final index = commitments.indexWhere((c) => c.id == id);
    final old = commitments[index];
    commitments[index] = fixedExpense(
      id,
      old.title,
      old.amount.minorUnits,
      categoryId: old.categoryId,
      dueDay: old.dueDay,
      paused: paused,
    );
    return commitments[index];
  }

  @override
  Future<FixedExpenseDto> pause(String id) async {
    calls.add('pause:$id');
    return _setPaused(id, true);
  }

  @override
  Future<FixedExpenseDto> resume(String id) async {
    calls.add('resume:$id');
    return _setPaused(id, false);
  }

  @override
  Future<OccurrenceDto> settle(
    String id,
    Period period, {
    int? amountMinor,
    String? settledOn,
  }) async {
    calls.add('settle:$id:${amountMinor ?? 'committed'}');
    lastSettledOn = settledOn;
    final c = commitments.firstWhere((c) => c.id == id);
    settled[id] = amountMinor ?? c.amount.minorUnits;
    return (await occurrences(period)).occurrences.firstWhere((o) => o.fixedExpenseId == id);
  }

  @override
  Future<OccurrenceDto> unsettle(String id, Period period) async {
    calls.add('unsettle:$id');
    settled.remove(id);
    return (await occurrences(period)).occurrences.firstWhere((o) => o.fixedExpenseId == id);
  }
}

Map<String, Object?> _date(String gregorian, String ethiopian) => {
  'gregorian': gregorian,
  'ethiopian': ethiopian,
  'ethiopian_month_name_am': 'ነሐሴ',
  'ethiopian_month_name_en': 'Nehase',
  'entered_in': 'gregorian',
};

FixedExpenseDto fixedExpense(
  String id,
  String title,
  int amountMinor, {
  String categoryId = 'c-rent',
  int dueDay = 5,
  bool paused = false,
  Period? start,
}) {
  final startPeriod = start ?? Period(CalendarKind.ethiopian, 2018, 12);
  return FixedExpenseDto.fromJson({
    'id': id,
    'category_id': categoryId,
    'category_name': 'Rent',
    'category_name_am': 'ቤት ኪራይ',
    'title': title,
    'amount': _m(amountMinor),
    'anchor_calendar': startPeriod.calendar.wire,
    'start_period': periodToJson(startPeriod),
    'end_period': null,
    'due_day': dueDay,
    'note': null,
    'is_paused': paused,
    'settled_periods': <Object?>[],
  });
}

class FakeCategoriesApi implements CategoriesApi {
  FakeCategoriesApi([List<CategoryDto> items = const [], this.inUse = const {}])
    : items = [...items];

  final List<CategoryDto> items;

  /// Ids that expenses use: removing one archives it instead of deleting.
  final Set<String> inUse;
  final List<String> calls = [];

  @override
  Future<List<CategoryDto>> list({bool includeArchived = false}) async =>
      items.where((c) => includeArchived || !c.isArchived).toList();

  @override
  Future<CategoryDto> create({
    required String name,
    String? nameAm,
    String? color,
    String? icon,
  }) async {
    calls.add('create:$name:${nameAm ?? ''}:${color ?? ''}:${icon ?? ''}');
    final created = category(
      'cat-new-${items.length}',
      name,
      nameAm: nameAm,
      color: color ?? '#607D8B',
      icon: icon,
    );
    items.add(created);
    return created;
  }

  @override
  Future<CategoryDto> update(
    String id, {
    String? name,
    String? nameAm,
    String? color,
    String? icon,
  }) async {
    calls.add('update:$id:${name ?? '-'}:${nameAm ?? '-'}:${color ?? '-'}:${icon ?? '-'}');
    final i = items.indexWhere((c) => c.id == id);
    final old = items[i];
    items[i] = category(
      id,
      name ?? old.name,
      nameAm: nameAm ?? old.nameAm,
      color: color ?? old.color,
      icon: icon ?? old.icon,
    );
    return items[i];
  }

  @override
  Future<CategoryDto?> remove(String id) async {
    calls.add('remove:$id');
    final i = items.indexWhere((c) => c.id == id);
    if (inUse.contains(id)) {
      final old = items[i];
      items[i] = category(
        id,
        old.name,
        nameAm: old.nameAm,
        color: old.color,
        icon: old.icon,
        archived: true,
      );
      return items[i];
    }
    items.removeAt(i);
    return null;
  }

  @override
  Future<CategoryDto> restore(String id) async {
    calls.add('restore:$id');
    final i = items.indexWhere((c) => c.id == id);
    final old = items[i];
    items[i] = category(id, old.name, nameAm: old.nameAm, color: old.color, icon: old.icon);
    return items[i];
  }
}

class FakeUnitsApi implements UnitsApi {
  FakeUnitsApi([this._items = const []]);
  final List<UnitDto> _items;

  @override
  Future<List<UnitDto>> list() async => _items;

  @override
  Future<UnitDto> create({required String code, required String name, String? nameAm}) async =>
      throw UnimplementedError();
}

class FakeItemsApi implements ItemsApi {
  FakeItemsApi([this._items = const []]);
  final List<ItemDto> _items;

  @override
  Future<List<ItemDto>> list({bool includeArchived = false}) async => _items;

  @override
  Future<ItemDto> create({required String name, String? nameAm, String? defaultUnitId}) async =>
      throw UnimplementedError();

  @override
  Future<ItemDto> get(String id) async => throw UnimplementedError();

  @override
  Future<ItemDto?> remove(String id) async => null;
}

CategoryDto category(
  String id,
  String name, {
  String? nameAm,
  String color = '#607D8B',
  String? icon,
  bool archived = false,
}) => CategoryDto.fromJson({
  'id': id,
  'name': name,
  'name_am': nameAm,
  'color': color,
  'icon': icon,
  'is_archived': archived,
  'is_default': false,
});

UnitDto unit(String id, String code, String name, {String? nameAm}) =>
    UnitDto.fromJson({'id': id, 'code': code, 'name': name, 'name_am': nameAm, 'is_system': true});

ExpenseDto _expense({
  required String categoryId,
  required int amountMinor,
  required String date,
  String? categoryName,
}) => ExpenseDto.fromJson({
  'id': 'exp-${DateTime.now().microsecondsSinceEpoch}',
  'category_id': categoryId,
  'amount': {'amount_minor': amountMinor, 'currency': 'ETB'},
  'spent_on': {
    'gregorian': date,
    'ethiopian': '2018-12-29',
    'ethiopian_month_name_am': 'ነሐሴ',
    'ethiopian_month_name_en': 'Nehase',
    'entered_in': 'gregorian',
  },
  'note': null,
  'payment_method': 'cash',
  'category_name': categoryName,
  'category_name_am': null,
  'item': null,
});

ExpenseDto expenseRow({
  required String id,
  required int amountMinor,
  String? categoryName,
  Map<String, Object?>? item,
}) => ExpenseDto.fromJson({
  'id': id,
  'category_id': 'cat-1',
  'amount': {'amount_minor': amountMinor, 'currency': 'ETB'},
  'spent_on': {
    'gregorian': '2026-09-04',
    'ethiopian': '2018-12-29',
    'ethiopian_month_name_am': 'ነሐሴ',
    'ethiopian_month_name_en': 'Nehase',
    'entered_in': 'gregorian',
  },
  'note': null,
  'payment_method': 'cash',
  'category_name': categoryName,
  'category_name_am': null,
  'item': item,
});

ExpensePageDto pageOf(List<ExpenseDto> items, {int? totalAmountMinor}) => ExpensePageDto.fromJson({
  'items': items
      .map(
        (e) => {
          'id': e.id,
          'category_id': e.categoryId,
          'amount': {'amount_minor': e.amount.minorUnits, 'currency': e.amount.currency},
          'spent_on': e.spentOn.raw,
          'note': e.note,
          'payment_method': e.paymentMethod,
          'category_name': e.categoryName,
          'category_name_am': e.categoryNameAm,
          'item': e.item == null
              ? null
              : {
                  'item_id': e.item!.itemId,
                  'item_name': e.item!.itemName,
                  'item_name_am': e.item!.itemNameAm,
                  'quantity': e.item!.quantity,
                  'quantity_milli': e.item!.quantityMilli,
                  'unit_id': e.item!.unitId,
                  'unit_code': e.item!.unitCode,
                  'unit_name': e.item!.unitName,
                  'unit_name_am': e.item!.unitNameAm,
                },
        },
      )
      .toList(),
  'total': items.length,
  'limit': 50,
  'offset': 0,
  'total_amount': {
    'amount_minor': totalAmountMinor ?? items.fold<int>(0, (sum, e) => sum + e.amount.minorUnits),
    'currency': 'ETB',
  },
});

/// In-memory budgets: the overall one under the key null, categories by id.
class FakeBudgetsApi implements BudgetsApi {
  FakeBudgetsApi([Map<String?, int>? initial]) : amounts = {...?initial};

  final Map<String?, int> amounts;
  final List<String> calls = [];

  BudgetDto _dto(String? categoryId) => BudgetDto.fromJson({
    'id': 'b-${categoryId ?? 'overall'}',
    'category_id': categoryId,
    'amount': _m(amounts[categoryId]!),
  });

  @override
  Future<List<BudgetDto>> list() async => [for (final key in amounts.keys) _dto(key)];

  @override
  Future<BudgetDto> setOverall(int amountMinor) async {
    calls.add('set:overall:$amountMinor');
    amounts[null] = amountMinor;
    return _dto(null);
  }

  @override
  Future<void> clearOverall() async {
    calls.add('clear:overall');
    amounts.remove(null);
  }

  @override
  Future<BudgetDto> setForCategory(String categoryId, int amountMinor) async {
    calls.add('set:$categoryId:$amountMinor');
    amounts[categoryId] = amountMinor;
    return _dto(categoryId);
  }

  @override
  Future<void> clearForCategory(String categoryId) async {
    calls.add('clear:$categoryId');
    amounts.remove(categoryId);
  }
}

/// Records profile pushes and password changes; never touches the token store.
class FakeAuthApi implements AuthApi {
  FakeAuthApi({
    this.passwordError,
    this.signInProviders = const SignInProvidersDto(),
    this.socialError,
  });

  final ApiException? passwordError;
  final SignInProvidersDto signInProviders;
  final ApiException? socialError;
  final List<Map<String, Object?>> socialCalls = [];
  final List<Map<String, Object?>> updates = [];
  final List<Map<String, String>> passwordChanges = [];

  @override
  Future<ProfileDto> updateMe({String? displayName, String? calendar, String? language}) async {
    updates.add({'display_name': displayName, 'calendar': calendar, 'language': language});
    return profile(
      displayName: displayName ?? 'Test',
      calendar: calendar ?? 'ethiopian',
      language: language ?? 'am',
    );
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (passwordError != null) throw passwordError!;
    passwordChanges.add({'current': currentPassword, 'new': newPassword});
  }

  @override
  Future<ProfileDto> me() async => profile();

  @override
  Future<SignInProvidersDto> providers() async => signInProviders;

  @override
  Future<AuthResultDto> social({
    required String provider,
    required String token,
    String? nonce,
    String? displayName,
    String? calendar,
    String? language,
    String? currency,
  }) async {
    socialCalls.add({
      'provider': provider,
      'token': token,
      'display_name': displayName,
      'calendar': calendar,
      'language': language,
      'currency': currency,
    });
    if (socialError != null) throw socialError!;
    return AuthResultDto(
      token: 'kise-token',
      expiresAt: '2026-12-01T00:00:00+00:00',
      owner: profile(displayName: displayName ?? 'Test'),
      created: true,
    );
  }

  @override
  Future<AuthResultDto> login({required String email, required String password}) async =>
      throw UnimplementedError();

  @override
  Future<AuthResultDto> register({
    required String email,
    required String password,
    required String displayName,
    String? calendar,
    String? language,
    String? currency,
  }) async => throw UnimplementedError();

  @override
  Future<void> signOut() async {}
}

ProfileDto profile({
  String displayName = 'Test',
  String calendar = 'ethiopian',
  String language = 'am',
  String currency = 'ETB',
}) => ProfileDto.fromJson({
  'id': 'owner-1',
  'email': 'test@example.com',
  'display_name': displayName,
  'calendar': calendar,
  'language': language,
  'currency': currency,
  'registered_at': '2026-09-01T00:00:00+00:00',
});

/// A scripted assistant: answers with whatever the test set, and records what it was sent.
class FakeAssistantApi implements AssistantApi {
  FakeAssistantApi({
    this.enabled = true,
    this.allowed = true,
    this.maxVoiceSeconds = 60,
    this.usage = const {},
    this.reply,
    this.answer = '',
    this.error,
  });

  final bool enabled;

  /// The plan's longest voice note.
  final int maxVoiceSeconds;

  /// This month's receipt scans and voice notes, by kind.
  final Map<String, UsageDto> usage;

  /// The account's plan includes the assistant.
  final bool allowed;
  DraftReplyDto? reply;
  String answer;
  ApiException? error;
  final List<Map<String, Object?>> calls = [];

  DraftReplyDto _reply() {
    if (error != null) throw error!;
    return reply ?? DraftReplyDto.fromJson({'message': '', 'drafts': <Object?>[]});
  }

  /// How many times status() was asked for.
  int statusCalls = 0;

  @override
  Future<AssistantStatusDto> status() async {
    statusCalls++;
    return AssistantStatusDto(
      enabled: enabled,
      allowed: allowed,
      hourlyLimit: 30,
      maxVoiceSeconds: maxVoiceSeconds,
      usage: usage,
      resetsOn: '2026-10-01',
    );
  }

  @override
  Future<DraftReplyDto> readText(String text, {required String today}) async {
    calls.add({'kind': 'text', 'text': text, 'today': today});
    return _reply();
  }

  @override
  Future<DraftReplyDto> readVoice(
    List<int> bytes, {
    required String contentType,
    required String today,
    String filename = 'voice.m4a',
  }) async {
    calls.add({'kind': 'voice', 'bytes': bytes, 'type': contentType, 'today': today});
    return _reply();
  }

  @override
  Future<DraftReplyDto> readReceipt(
    List<int> bytes, {
    required String contentType,
    required String today,
    String filename = 'receipt.jpg',
  }) async {
    calls.add({'kind': 'receipt', 'bytes': bytes, 'type': contentType, 'today': today});
    return _reply();
  }

  @override
  Future<String> ask(String question, {required String today}) async {
    calls.add({'kind': 'ask', 'question': question, 'today': today});
    if (error != null) throw error!;
    return answer;
  }

  /// What a spoken question was heard as.
  String? heard;

  @override
  Future<AnswerDto> askVoice(
    List<int> bytes, {
    required String contentType,
    required String today,
    String filename = 'question.m4a',
  }) async {
    calls.add({'kind': 'ask-voice', 'bytes': bytes, 'type': contentType, 'today': today});
    if (error != null) throw error!;
    return AnswerDto(answer: answer, transcript: heard);
  }
}

/// A draft as the server sends it.
DraftExpenseDto draftOf({
  String categoryId = 'c1',
  String categoryName = 'Taxi',
  int amountMinor = 15000,
  String gregorian = '2026-09-04',
  String ethiopian = '2018-12-29',
  String paymentMethod = 'cash',
  String? note,
  Map<String, Object?>? item,
  List<String> warnings = const [],
  String? newCategory,
}) => DraftExpenseDto.fromJson({
  'new_category': newCategory,
  'category_id': categoryId,
  'category_name': categoryName,
  'category_name_am': null,
  'amount': _m(amountMinor),
  'spent_on': _date(gregorian, ethiopian),
  'payment_method': paymentMethod,
  'note': note,
  'item': item,
  'warnings': warnings,
});

DraftReplyDto replyOf(
  List<DraftExpenseDto> drafts, {
  String message = '',
  String? transcript,
  List<FixedDraftDto> fixed = const [],
  List<PaymentDraftDto> payments = const [],
}) => DraftReplyDto(
  message: message,
  transcript: transcript,
  merchant: null,
  drafts: drafts,
  fixedDrafts: fixed,
  paymentDrafts: payments,
);

FixedDraftDto fixedDraftOf({
  String title = 'Rent',
  String categoryId = 'c1',
  int amountMinor = 800000,
  int dueDay = 5,
  Map<String, Object?> start = const {'calendar': 'ethiopian', 'year': 2018, 'month': 13},
  List<String> warnings = const [],
}) => FixedDraftDto.fromJson({
  'title': title,
  'category_id': categoryId,
  'category_name': 'Taxi',
  'category_name_am': null,
  'amount': _m(amountMinor),
  'due_day': dueDay,
  'start_period': start,
  'note': null,
  'warnings': warnings,
});

PaymentDraftDto paymentDraftOf({
  String id = 'fx-1',
  String title = 'Rent',
  int amountMinor = 800000,
  List<String> warnings = const [],
}) => PaymentDraftDto.fromJson({
  'fixed_expense_id': id,
  'title': title,
  'period': {'calendar': 'ethiopian', 'year': 2018, 'month': 12},
  'amount': _m(amountMinor),
  'paid_on': _date('2026-09-04', '2018-12-29'),
  'warnings': warnings,
});

/// How to pay for Pro, as the portal would have set it. [ready] false is "not set up yet".
class FakePlansApi implements PlansApi {
  FakePlansApi({PaymentInfoDto? payment}) : _payment = payment ?? PaymentInfoDto.notReady;

  final PaymentInfoDto _payment;
  int calls = 0;

  @override
  Future<PaymentInfoDto> payment() async {
    calls++;
    return _payment;
  }
}

/// A complete set of payment details: two accounts, Telegram, phone and email.
PaymentInfoDto fakePaymentInfo({String note = ''}) => PaymentInfoDto.fromJson({
  'ready': true,
  'accounts': [
    {'bank': 'Commercial Bank of Ethiopia', 'holder': 'Kise PLC', 'number': '1000123456789'},
    {'bank': 'telebirr', 'holder': 'Kise PLC', 'number': '0911234567'},
  ],
  'plans': [
    {'plan': 'basic', 'price': '100 birr a month', 'ai_enabled': false},
    {'plan': 'pro', 'price': '300 birr a month', 'ai_enabled': true},
  ],
  'telegram': 'kise_support',
  'telegram_url': 'https://t.me/kise_support',
  'phone': '+251 911 234 567',
  'email': 'pay@kise.example',
  'note': note,
  'reference': 'test@example.com',
});

/// Provider overrides that replace the network-backed data sources with fakes, and force the
/// session to signed-in so gated screens render.
List<Override> fakeApiOverrides({
  FakeExpensesApi? expenses,
  FakeCategoriesApi? categories,
  FakeUnitsApi? units,
  FakeItemsApi? items,
  FakeMonthlySummaryApi? summary,
  FakeFixedExpensesApi? fixedExpenses,
  FakeBudgetsApi? budgets,
  FakeAuthApi? auth,
  FakeAssistantApi? assistant,
  FakePlansApi? plans,
  Map<String, Object?>? plan,
}) => [
  plansApiProvider.overrideWithValue(plans ?? FakePlansApi()),
  assistantApiProvider.overrideWithValue(assistant ?? FakeAssistantApi(enabled: false)),
  budgetsApiProvider.overrideWithValue(budgets ?? FakeBudgetsApi()),
  authApiProvider.overrideWithValue(auth ?? FakeAuthApi()),
  expensesApiProvider.overrideWithValue(expenses ?? FakeExpensesApi()),
  monthlySummaryApiProvider.overrideWithValue(summary ?? FakeMonthlySummaryApi()),
  fixedExpensesApiProvider.overrideWithValue(fixedExpenses ?? FakeFixedExpensesApi()),
  itemUsageReportsApiProvider.overrideWithValue(FakeItemUsageReportsApi()),
  categoriesApiProvider.overrideWithValue(categories ?? FakeCategoriesApi()),
  unitsApiProvider.overrideWithValue(units ?? FakeUnitsApi()),
  itemsApiProvider.overrideWithValue(items ?? FakeItemsApi()),
  sessionProvider.overrideWith(() => _SignedInSession(plan)),
];

/// A session that is already signed in, so the gate lets the app through in tests.
class _SignedInSession extends SessionController {
  _SignedInSession(this._plan);

  final Map<String, Object?>? _plan;

  @override
  Future<SessionState> build() async => SignedIn(
    ProfileDto.fromJson({
      'id': 'owner-1',
      'email': 'test@example.com',
      'display_name': 'Test',
      'calendar': 'ethiopian',
      'language': 'am',
      'currency': 'ETB',
      'registered_at': '2026-09-01T00:00:00+00:00',
      'plan': ?_plan,
    }),
  );
}
