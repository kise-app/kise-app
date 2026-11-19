/// Budgets data source: monthly spending limits, overall and per category.
///
/// Setting is idempotent on the server (a `PUT`), so the app never has to know whether a budget
/// already exists. How a month is doing against them comes back in the monthly summary.
library;

import '../../../shared_kernel/money.dart';
import '../api_client.dart';

class BudgetDto {
  const BudgetDto({required this.id, required this.categoryId, required this.amount});

  final String id;

  /// Null for the overall budget.
  final String? categoryId;
  final Money amount;

  bool get isOverall => categoryId == null;

  factory BudgetDto.fromJson(Map<String, Object?> json) => BudgetDto(
        id: json['id'] as String,
        categoryId: json['category_id'] as String?,
        amount: Money.fromJson((json['amount'] as Map).cast<String, Object?>()),
      );
}

class BudgetsApi {
  BudgetsApi(this._client);

  final ApiClient _client;

  static const _base = '/api/budgets';

  Future<List<BudgetDto>> list() async {
    final data = await _client.get(_base);
    return (data as List)
        .map((b) => BudgetDto.fromJson((b as Map).cast<String, Object?>()))
        .toList();
  }

  Future<BudgetDto> setOverall(int amountMinor) async {
    final data = await _client.put('$_base/overall', body: {'amount_minor': amountMinor});
    return BudgetDto.fromJson((data as Map).cast<String, Object?>());
  }

  Future<void> clearOverall() => _client.delete('$_base/overall');

  Future<BudgetDto> setForCategory(String categoryId, int amountMinor) async {
    final data = await _client.put(
      '$_base/categories/$categoryId',
      body: {'amount_minor': amountMinor},
    );
    return BudgetDto.fromJson((data as Map).cast<String, Object?>());
  }

  Future<void> clearForCategory(String categoryId) =>
      _client.delete('$_base/categories/$categoryId');
}
