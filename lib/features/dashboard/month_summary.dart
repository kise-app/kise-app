/// The dashboard's month, as the widgets read it.
///
/// A thin layer over [MonthlySummaryDto] that turns minor units into [Money] in the currency label
/// from Settings and adds the derived figures the cards need (peak day, daily average, largest
/// category first). Keeping the derivations here means the widgets stay pure layout.
library;

import '../../platform/api/api.dart';
import '../../shared_kernel/money.dart';

class MonthSummary {
  MonthSummary(this.dto, this.currency);

  /// An empty month of [days] days — shown while the first response is loading or when it failed.
  factory MonthSummary.empty(int days, String currency) =>
      MonthSummary(MonthlySummaryDto.empty(days, currency: currency), currency);

  final MonthlySummaryDto dto;
  final String currency;

  Money _money(int minor) => Money(minor, currency);

  Money get committed => _money(dto.committedMinor);

  Money get settled => _money(dto.settledMinor);

  Money get outstanding => _money(dto.outstandingMinor);

  Money get dynamicTotal => _money(dto.dynamicTotalMinor);

  Money get grandTotal => committed + dynamicTotal;

  Money get previousTotal => _money(dto.previousTotalMinor);

  int get expenseCount => dto.expenseCount;

  bool get isEmpty => grandTotal.isZero;

  /// Largest first — the order every breakdown on the dashboard uses.
  List<CategorySpendDto> get categoriesBySize =>
      [...dto.categories]..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));

  /// One entry per day of the month, in minor units. Dynamic spending only.
  List<int> get daily => dto.dailyMinor;

  int get peakDaily => daily.isEmpty ? 0 : daily.reduce((a, b) => a > b ? a : b);

  /// Zero-based index of the busiest day.
  int get peakDayIndex => daily.indexOf(peakDaily);

  /// Average per day over the first [days] days (all of them when null). For the current month the
  /// caller passes the days elapsed, so the future does not drag the average down.
  int averageDaily({int? days}) {
    if (daily.isEmpty) return 0;
    final count = (days ?? daily.length).clamp(1, daily.length);
    return daily.take(count).fold<int>(0, (sum, value) => sum + value) ~/ count;
  }
}
