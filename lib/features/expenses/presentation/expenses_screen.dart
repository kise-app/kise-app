/// The expenses tab: the month's recorded spending, newest first.
///
/// It reads [expensesForPeriodProvider] — keyed to the selected month, which the navigator under the
/// title shares with the dashboard — and renders each expense with its amount, category, date (in
/// the owner's calendar) and, when present, the item line ("12 kg of Sugar"). A header shows how
/// many expenses match and what they add up to.
///
/// * **Search** finds text in the note or the item name ("sugar", "Bole").
/// * **Filter** narrows by category and payment method; active filters show as chips to remove.
/// * The list loads 50 at a time and fetches the next page as it scrolls.
/// * Tap an expense to edit it; swipe it left to delete (after a confirmation).
///
/// Empty and error states are explicit rather than a blank screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/api/api.dart';
import '../../../platform/settings.dart';
import '../../../shared/month_data.dart';
import '../../../shared/widgets/gradient_action_button.dart';
import '../../../shared/widgets/period_navigator.dart';
import '../../../shared_kernel/money.dart';
import 'expense_form_sheet.dart';
import 'expense_providers.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final list = ref.watch(expensesForPeriodProvider);
    final filter = ref.watch(expenseFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.say('ወጪዎች', 'Expenses')),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(76),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: PeriodNavigator(keyPrefix: 'expenses-'),
          ),
        ),
      ),
      body: Column(
        children: [
          _SearchAndFilters(settings: settings, filter: filter),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(expensesForPeriodProvider);
                await ref.read(expensesForPeriodProvider.future).then((_) {}, onError: (_) {});
              },
              child: switch (list) {
                AsyncValue(:final valueOrNull?) =>
                  valueOrNull.items.isEmpty
                      ? _EmptyState(
                          settings: settings,
                          filtered: filter.isActive,
                          onClear: () => ref.read(expenseFilterProvider.notifier).state =
                              const ExpenseListFilter(),
                        )
                      : _ExpenseList(list: valueOrNull, settings: settings),
                AsyncValue(:final error?) => _ErrorState(
                  message: error is ApiException
                      ? error.message
                      : settings.say('ወጪዎችን መጫን አልተቻለም', 'Could not load expenses'),
                  onRetry: () => ref.invalidate(expensesForPeriodProvider),
                  retryLabel: settings.say('እንደገና ሞክር', 'Retry'),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ),
        ],
      ),
      floatingActionButton: GradientActionButton(
        key: const Key('expenses-add'),
        icon: Icons.add_rounded,
        label: settings.say('ወጪ መዝግብ', 'Add expense'),
        onPressed: () => showExpenseForm(context),
      ),
    );
  }
}

/// The search field, the filter button, and a chip per active filter.
class _SearchAndFilters extends ConsumerStatefulWidget {
  const _SearchAndFilters({required this.settings, required this.filter});

  final AppSettings settings;
  final ExpenseListFilter filter;

  @override
  ConsumerState<_SearchAndFilters> createState() => _SearchAndFiltersState();
}

class _SearchAndFiltersState extends ConsumerState<_SearchAndFilters> {
  late final TextEditingController _search = TextEditingController(text: widget.filter.search);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _setFilter(ExpenseListFilter Function(ExpenseListFilter) change) {
    final notifier = ref.read(expenseFilterProvider.notifier);
    notifier.state = change(notifier.state);
  }

  /// Wait for a pause in typing, so "sugar" is one request rather than five.
  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _setFilter((f) => f.copyWith(search: text.trim()));
    });
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _FilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final filter = widget.filter;
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <CategoryDto>[];
    final names = {
      for (final c in categories) c.id: settings.isAmharic ? (c.nameAm ?? c.name) : c.name,
    };
    final filterCount = filter.categoryIds.length + filter.paymentMethods.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('expenses-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: settings.say('ማስታወሻ ወይም ዕቃ ፈልግ', 'Search notes or items'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: settings.say('አጥፋ', 'Clear'),
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _debounce?.cancel();
                              _search.clear();
                              _setFilter((f) => f.copyWith(search: ''));
                              setState(() {});
                            },
                          ),
                  ),
                  onChanged: (text) {
                    setState(() {});
                    _onSearchChanged(text);
                  },
                  onSubmitted: (text) {
                    _debounce?.cancel();
                    _setFilter((f) => f.copyWith(search: text.trim()));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: filterCount > 0,
                label: Text('$filterCount'),
                child: IconButton.filledTonal(
                  key: const Key('expenses-filter'),
                  tooltip: settings.say('አጣራ', 'Filter'),
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: _openFilters,
                ),
              ),
            ],
          ),
          if (filterCount > 0)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  for (final id in filter.categoryIds)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        key: Key('active-filter-$id'),
                        deleteIcon: const Icon(Icons.close_rounded, size: 18),
                        label: Text(names[id] ?? settings.say('ምድብ', 'Category')),
                        onDeleted: () => _setFilter(
                          (f) => f.copyWith(categoryIds: {...f.categoryIds}..remove(id)),
                        ),
                      ),
                    ),
                  for (final method in filter.paymentMethods)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        key: Key('active-filter-$method'),
                        deleteIcon: const Icon(Icons.close_rounded, size: 18),
                        label: Text(paymentMethodLabel(method, settings)),
                        onDeleted: () => _setFilter(
                          (f) => f.copyWith(paymentMethods: {...f.paymentMethods}..remove(method)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Pick categories and payment methods; every tap applies at once, so there is no "apply" step.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final filter = ref.watch(expenseFilterProvider);
    final categories = ref.watch(categoriesProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(expenseFilterProvider.notifier);

    Set<String> toggled(Set<String> values, String value) =>
        values.contains(value) ? ({...values}..remove(value)) : {...values, value};

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    settings.say('አጣራ', 'Filter expenses'),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (filter.categoryIds.isNotEmpty || filter.paymentMethods.isNotEmpty)
                  TextButton(
                    key: const Key('filter-clear'),
                    onPressed: () => notifier.state = filter.copyWith(
                      categoryIds: const {},
                      paymentMethods: const {},
                    ),
                    child: Text(settings.say('ሁሉንም አጥፋ', 'Clear all')),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(settings.say('ምድብ', 'Category'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            categories.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Text(settings.say('ምድቦችን መጫን አልተቻለም', 'Could not load categories')),
              data: (list) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in list)
                    FilterChip(
                      key: Key('filter-category-${c.id}'),
                      label: Text(settings.isAmharic ? (c.nameAm ?? c.name) : c.name),
                      selected: filter.categoryIds.contains(c.id),
                      onSelected: (_) => notifier.state = filter.copyWith(
                        categoryIds: toggled(filter.categoryIds, c.id),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(settings.say('የክፍያ ዘዴ', 'Payment method'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in paymentMethods)
                  FilterChip(
                    key: Key('filter-payment-$method'),
                    label: Text(paymentMethodLabel(method, settings)),
                    selected: filter.paymentMethods.contains(method),
                    onSelected: (_) => notifier.state = filter.copyWith(
                      paymentMethods: toggled(filter.paymentMethods, method),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('filter-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(settings.say('ተጠናቀቀ', 'Done')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseList extends ConsumerWidget {
  const _ExpenseList({required this.list, required this.settings});

  final ExpenseListState list;
  final AppSettings settings;

  Future<bool> _delete(BuildContext context, WidgetRef ref, ExpenseDto expense) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await confirmDeleteExpense(context, settings)) return false;
    try {
      await ref.read(expensesApiProvider).delete(expense.id);
    } on ApiException catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
      return false;
    }
    invalidateMonthData(ref);
    messenger?.showSnackBar(SnackBar(content: Text(settings.say('ወጪው ተሰርዟል', 'Expense deleted'))));
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = list.items;
    // Header, the rows, then a footer that shows the next page loading.
    final footer = list.hasMore ? 1 : 0;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (list.hasMore && notification.metrics.extentAfter < 400) {
          ref.read(expensesForPeriodProvider.notifier).loadMore().catchError((_) {});
        }
        return false;
      },
      child: ListView.separated(
        key: const Key('expenses-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length + 1 + footer,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          if (index == items.length + 1) {
            return Padding(
              key: const Key('expenses-loading-more'),
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: list.loadingMore
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: () => ref
                            .read(expensesForPeriodProvider.notifier)
                            .loadMore()
                            .catchError((_) {}),
                        child: Text(settings.say('ተጨማሪ አሳይ', 'Load more')),
                      ),
              ),
            );
          }
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    settings.say('${list.total} ወጪዎች', '${list.total} expenses'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    Money(list.totalAmount.minorUnits, list.totalAmount.currency).format(),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            );
          }
          final expense = items[index - 1];
          return Dismissible(
            key: ValueKey('expense-${expense.id}'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _delete(context, ref, expense),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.onErrorContainer),
            ),
            child: _ExpenseTile(
              expense: expense,
              settings: settings,
              onTap: () => showExpenseForm(context, expense: expense),
            ),
          );
        },
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense, required this.settings, required this.onTap});

  final ExpenseDto expense;
  final AppSettings settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryName = settings.isAmharic
        ? (expense.categoryNameAm ?? expense.categoryName ?? '')
        : (expense.categoryName ?? '');
    final dateLabel = settings.isAmharic
        ? '${expense.spentOn.ethiopianMonthNameAm} · ${expense.spentOn.ethiopian}'
        : expense.spentOn.gregorian;
    final item = expense.item;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        key: Key('expense-tile-${expense.id}'),
        onTap: onTap,
        title: Text(
          categoryName.isEmpty ? settings.say('ወጪ', 'Expense') : categoryName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateLabel, style: theme.textTheme.bodySmall),
            if (item != null)
              Text(
                '${item.quantity} ${item.unitCode ?? ''} · '
                '${settings.isAmharic ? (item.itemNameAm ?? item.itemName ?? '') : (item.itemName ?? '')}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
              ),
            if (expense.note != null && expense.note!.isNotEmpty)
              Text(expense.note!, style: theme.textTheme.bodySmall),
          ],
        ),
        trailing: Text(
          Money(expense.amount.minorUnits, expense.amount.currency).format(),
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.settings, required this.filtered, required this.onClear});

  final AppSettings settings;

  /// Nothing matched the search/filter, rather than nothing recorded at all.
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    // A ListView so RefreshIndicator still works when empty.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(
          filtered ? Icons.search_off_rounded : Icons.receipt_long_outlined,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        if (filtered) ...[
          Text(
            settings.say('የሚዛመድ ወጪ የለም።', 'No expenses match.'),
            key: const Key('expenses-no-match'),
            textAlign: TextAlign.center,
            style: muted,
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              key: const Key('expenses-clear-filters'),
              onPressed: onClear,
              child: Text(settings.say('ማጣሪያውን አጥፋ', 'Clear search and filters')),
            ),
          ),
        ] else ...[
          Text(
            settings.say('በዚህ ወር ገና ወጪ የለም።', 'No expenses this month yet.'),
            key: const Key('expenses-empty'),
            textAlign: TextAlign.center,
            style: muted,
          ),
          const SizedBox(height: 6),
          Text(
            settings.say('ከታች ባለው ቁልፍ መዝግብ።', 'Add one with the button below.'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry, required this.retryLabel});

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 12),
        Text(
          message,
          key: const Key('expenses-error'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
        ),
      ],
    );
  }
}
