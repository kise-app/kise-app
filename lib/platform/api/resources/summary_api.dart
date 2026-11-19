/// Monthly summary data source: the dashboard's month in one request.
///
/// `GET /api/reports/summary` answers "how much did I spend in ሐምሌ?" with everything the dashboard
/// draws: the grand total (dynamic + committed), last month's total for the change line, fixed
/// committed / settled / outstanding, one dynamic-spending figure per day of the month, and the
/// category split. The Period is resolved on the server, so an Ethiopian month needs no client-side
/// calendar arithmetic.
///
/// Amounts are kept as integer minor units here. The dashboard wraps them in [Money] with the
/// currency label from Settings, exactly as it did with its placeholder data.
library;

import '../api_client.dart';

class CategorySpendDto {
  const CategorySpendDto({
    required this.categoryId,
    required this.name,
    required this.nameAm,
    required this.color,
    required this.icon,
    required this.totalMinor,
    required this.dynamicMinor,
    required this.committedMinor,
    required this.expenseCount,
    this.budgetMinor,
  });

  final String categoryId;
  final String name;
  final String? nameAm;

  /// `#RRGGBB`.
  final String color;

  /// A Material icon name such as `restaurant`, or null.
  final String? icon;
  final int totalMinor;
  final int dynamicMinor;
  final int committedMinor;
  final int expenseCount;

  /// The category's monthly limit, or null when none is set.
  final int? budgetMinor;

  String label(bool amharic) => amharic ? (nameAm ?? name) : name;

  factory CategorySpendDto.fromJson(Map<String, Object?> json) => CategorySpendDto(
        categoryId: json['category_id'] as String,
        name: json['name'] as String,
        nameAm: json['name_am'] as String?,
        color: json['color'] as String,
        icon: json['icon'] as String?,
        totalMinor: _minor(json['total']),
        dynamicMinor: _minor(json['dynamic']),
        committedMinor: _minor(json['committed']),
        expenseCount: (json['expense_count'] as num).toInt(),
        budgetMinor: _optionalMinor(json['budget']),
      );
}

class MonthlySummaryDto {
  const MonthlySummaryDto({
    required this.currency,
    required this.grandTotalMinor,
    required this.dynamicTotalMinor,
    required this.expenseCount,
    required this.committedMinor,
    required this.settledMinor,
    required this.outstandingMinor,
    required this.previousTotalMinor,
    required this.dailyMinor,
    required this.categories,
  });

  final String currency;
  final int grandTotalMinor;
  final int dynamicTotalMinor;
  final int expenseCount;
  final int committedMinor;
  final int settledMinor;
  final int outstandingMinor;
  final int previousTotalMinor;

  /// One entry per day of the month, dynamic spending only.
  final List<int> dailyMinor;

  /// Largest first.
  final List<CategorySpendDto> categories;

  /// An empty month of [days] days, for the moment before the first response arrives.
  factory MonthlySummaryDto.empty(int days, {String currency = 'ETB'}) => MonthlySummaryDto(
        currency: currency,
        grandTotalMinor: 0,
        dynamicTotalMinor: 0,
        expenseCount: 0,
        committedMinor: 0,
        settledMinor: 0,
        outstandingMinor: 0,
        previousTotalMinor: 0,
        dailyMinor: List<int>.filled(days, 0),
        categories: const [],
      );

  factory MonthlySummaryDto.fromJson(Map<String, Object?> json) => MonthlySummaryDto(
        currency: json['currency'] as String,
        grandTotalMinor: _minor(json['grand_total']),
        dynamicTotalMinor: _minor(json['dynamic_total']),
        expenseCount: (json['expense_count'] as num).toInt(),
        committedMinor: _minor(json['committed']),
        settledMinor: _minor(json['settled']),
        outstandingMinor: _minor(json['outstanding']),
        previousTotalMinor: _minor(json['previous_total']),
        dailyMinor: (json['daily_minor'] as List).map((v) => (v as num).toInt()).toList(),
        categories: (json['categories'] as List)
            .map((c) => CategorySpendDto.fromJson((c as Map).cast<String, Object?>()))
            .toList(),
      );
}

int _minor(Object? money) => ((money as Map)['amount_minor'] as num).toInt();

int? _optionalMinor(Object? money) => money is Map ? (money['amount_minor'] as num).toInt() : null;

class MonthlySummaryApi {
  MonthlySummaryApi(this._client);

  final ApiClient _client;

  Future<MonthlySummaryDto> forPeriod({
    required int year,
    required int month,
    String calendar = 'ethiopian',
  }) async {
    final data = await _client.get('/api/reports/summary', query: {
      'period_year': year,
      'period_month': month,
      'period_calendar': calendar,
    });
    return MonthlySummaryDto.fromJson((data as Map).cast<String, Object?>());
  }
}
