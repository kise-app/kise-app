/// Providers that feed the expense screens: the pickers' data (categories, units, items).
///
/// Each is a `FutureProvider` over the reusable API data sources, so a screen reads
/// `ref.watch(categoriesProvider)` and gets an `AsyncValue` it can render as loading / error / data
/// without owning any fetch logic. The month-keyed list lives in `shared/month_data.dart`, beside
/// the other month views it must refresh together with; it is re-exported here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/api/api.dart';

export '../../../shared/month_data.dart'
    show expenseFilterProvider, expensesForPeriodProvider, ExpenseListFilter, invalidateMonthData;

/// The owner's categories, for the category picker.
final categoriesProvider = FutureProvider<List<CategoryDto>>((ref) async {
  return ref.watch(categoriesApiProvider).list();
});

/// The units of measurement, for the unit picker on the item line.
final unitsProvider = FutureProvider<List<UnitDto>>((ref) async {
  return ref.watch(unitsApiProvider).list();
});

/// The owner's items, for the "pick an existing item" suggestions.
final itemsProvider = FutureProvider<List<ItemDto>>((ref) async {
  return ref.watch(itemsApiProvider).list();
});
