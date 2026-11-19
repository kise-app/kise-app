/// Everything the app fetches for the month being viewed, in one place.
///
/// Each provider is keyed to [selectedPeriodProvider], so stepping months refetches. Several
/// screens show overlapping numbers — recording an expense changes the expenses list *and* the
/// dashboard; settling rent changes the Fixed tab *and* the dashboard — so anything that writes
/// calls [invalidateMonthData] rather than remembering which providers to refresh.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/api/api.dart';
import '../platform/settings.dart';
import '../shared_kernel/money.dart';
import '../shared_kernel/period.dart';

/// How the expenses list is narrowed: free text (note or item name), categories, payment methods.
class ExpenseListFilter {
  const ExpenseListFilter({
    this.search = '',
    this.categoryIds = const {},
    this.paymentMethods = const {},
  });

  final String search;
  final Set<String> categoryIds;
  final Set<String> paymentMethods;

  bool get isActive =>
      search.trim().isNotEmpty || categoryIds.isNotEmpty || paymentMethods.isNotEmpty;

  ExpenseListFilter copyWith({
    String? search,
    Set<String>? categoryIds,
    Set<String>? paymentMethods,
  }) => ExpenseListFilter(
    search: search ?? this.search,
    categoryIds: categoryIds ?? this.categoryIds,
    paymentMethods: paymentMethods ?? this.paymentMethods,
  );

  @override
  bool operator ==(Object other) =>
      other is ExpenseListFilter &&
      other.search == search &&
      _sameSet(other.categoryIds, categoryIds) &&
      _sameSet(other.paymentMethods, paymentMethods);

  @override
  int get hashCode => Object.hash(
    search,
    Object.hashAllUnordered(categoryIds),
    Object.hashAllUnordered(paymentMethods),
  );

  static bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
}

final expenseFilterProvider = StateProvider<ExpenseListFilter>((ref) => const ExpenseListFilter());

/// One loaded run of the expenses list: the pages fetched so far plus the filter's totals.
class ExpenseListState {
  const ExpenseListState({
    required this.items,
    required this.total,
    required this.totalAmount,
    this.loadingMore = false,
  });

  final List<ExpenseDto> items;

  /// How many expenses match, across every page.
  final int total;

  /// What they add up to, across every page.
  final Money totalAmount;
  final bool loadingMore;

  bool get hasMore => items.length < total;

  ExpenseListState copyWith({List<ExpenseDto>? items, bool? loadingMore}) => ExpenseListState(
    items: items ?? this.items,
    total: total,
    totalAmount: totalAmount,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// The expenses for the month being viewed, newest first, a page at a time.
///
/// Rebuilds from the first page whenever the month or the filter changes; [loadMore] appends the
/// next page as the list scrolls.
class ExpenseListController extends AsyncNotifier<ExpenseListState> {
  static const pageSize = 50;

  late Period _period;
  late ExpenseListFilter _filter;

  Future<ExpensePageDto> _fetch(int offset) {
    return ref
        .read(expensesApiProvider)
        .list(
          periodYear: _period.year,
          periodMonth: _period.month,
          periodCalendar: _period.calendar.wire,
          categoryIds: _filter.categoryIds.toList(),
          paymentMethods: _filter.paymentMethods.toList(),
          search: _filter.search,
          limit: pageSize,
          offset: offset,
        );
  }

  @override
  Future<ExpenseListState> build() async {
    _period = ref.watch(selectedPeriodProvider);
    _filter = ref.watch(expenseFilterProvider);
    final page = await _fetch(0);
    return ExpenseListState(items: page.items, total: page.total, totalAmount: page.totalAmount);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore || !current.hasMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    final period = _period;
    final filter = _filter;
    try {
      final page = await _fetch(current.items.length);
      // The month or filter changed while this page was in flight: it belongs to a stale list.
      if (period != _period || filter != _filter) return;
      state = AsyncData(
        current.copyWith(items: [...current.items, ...page.items], loadingMore: false),
      );
    } on ApiException {
      if (period == _period && filter == _filter) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

final expensesForPeriodProvider = AsyncNotifierProvider<ExpenseListController, ExpenseListState>(
  ExpenseListController.new,
);

/// Every budget the owner has set: the overall one and per category.
final budgetsProvider = FutureProvider<List<BudgetDto>>((ref) async {
  return ref.watch(budgetsApiProvider).list();
});

/// The overall monthly budget, or null when none is set.
final overallBudgetProvider = Provider<Money?>((ref) {
  final budgets = ref.watch(budgetsProvider).valueOrNull ?? const [];
  for (final budget in budgets) {
    if (budget.isOverall) return budget.amount;
  }
  return null;
});

/// The dashboard's month: totals, daily rhythm, category split.
final monthSummaryProvider = FutureProvider<MonthlySummaryDto>((ref) async {
  final period = ref.watch(selectedPeriodProvider);
  return ref
      .watch(monthlySummaryApiProvider)
      .forPeriod(year: period.year, month: period.month, calendar: period.calendar.wire);
});

/// The fixed commitments owed in the month being viewed.
final occurrencesProvider = FutureProvider<OccurrenceMonthDto>((ref) async {
  final period = ref.watch(selectedPeriodProvider);
  return ref.watch(fixedExpensesApiProvider).occurrences(period);
});

/// Every commitment the owner has, paused or not, for managing them.
final fixedExpensesProvider = FutureProvider<List<FixedExpenseDto>>((ref) async {
  return ref.watch(fixedExpensesApiProvider).list();
});

/// The month's item usage ("12 kg sugar").
final itemUsageProvider = FutureProvider<ItemUsageReportDto>((ref) async {
  final period = ref.watch(selectedPeriodProvider);
  return ref
      .watch(itemUsageReportsApiProvider)
      .forPeriod(year: period.year, month: period.month, calendar: period.calendar.wire);
});

/// Refresh every month-keyed view after a write.
void invalidateMonthData(WidgetRef ref) {
  ref.invalidate(expensesForPeriodProvider);
  ref.invalidate(monthSummaryProvider);
  ref.invalidate(occurrencesProvider);
  ref.invalidate(fixedExpensesProvider);
  ref.invalidate(itemUsageProvider);
  ref.invalidate(budgetsProvider);
}

/// Older versions kept the monthly budget on the device. Upload it once — unless the account
/// already has one — then forget the local copy, so the server is the only source from now on.
Future<void> uploadLegacyBudget(WidgetRef ref) async {
  final local = ref.read(settingsProvider).monthlyBudgetMinor;
  if (local <= 0) return;
  final api = ref.read(budgetsApiProvider);
  try {
    final existing = await api.list();
    if (!existing.any((b) => b.isOverall)) await api.setOverall(local);
    ref.read(settingsProvider.notifier).clearBudget();
    ref.invalidate(budgetsProvider);
  } on ApiException {
    // Offline or refused: keep the local copy and try again next launch.
  }
}

/// How close a spend is to its limit, for colouring and alerts.
enum BudgetLevel {
  fine,

  /// 80% or more.
  near,

  /// Over the limit.
  over;

  static BudgetLevel of(int spentMinor, int budgetMinor) {
    if (budgetMinor <= 0) return BudgetLevel.fine;
    if (spentMinor > budgetMinor) return BudgetLevel.over;
    if (spentMinor * 5 >= budgetMinor * 4) return BudgetLevel.near;
    return BudgetLevel.fine;
  }
}
