/// Fixed Monthly Expenses data source: commitments like rent and internet, and the months paid.
///
/// A commitment recurs in the calendar it was created in (its *anchor* calendar). The app never does
/// that mapping itself: it asks [FixedExpensesApi.occurrences] for "what is owed in this month" in
/// whatever calendar the user is viewing, and each [OccurrenceDto] comes back carrying the anchor
/// [Period] it is filed under — which is the Period sent back to settle or unsettle it.
library;

import '../../../shared_kernel/money.dart';
import '../../../shared_kernel/period.dart';
import '../api_client.dart';
import 'expenses_api.dart';

/// Read the `{calendar, year, month, ...labels}` payload the backend sends for a Period.
Period periodFromJson(Map<String, Object?> json) => Period(
      CalendarKind.parse(json['calendar'] as String),
      (json['year'] as num).toInt(),
      (json['month'] as num).toInt(),
    );

Map<String, Object?> periodToJson(Period period) => {
      'year': period.year,
      'month': period.month,
      'calendar': period.calendar.wire,
    };

class FixedExpenseDto {
  const FixedExpenseDto({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.categoryNameAm,
    required this.title,
    required this.amount,
    required this.anchorCalendar,
    required this.startPeriod,
    required this.endPeriod,
    required this.dueDay,
    required this.note,
    required this.isPaused,
  });

  final String id;
  final String categoryId;
  final String? categoryName;
  final String? categoryNameAm;
  final String title;
  final Money amount;
  final CalendarKind anchorCalendar;
  final Period startPeriod;
  final Period? endPeriod;
  final int dueDay;
  final String? note;
  final bool isPaused;

  factory FixedExpenseDto.fromJson(Map<String, Object?> json) {
    final end = json['end_period'];
    return FixedExpenseDto(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      categoryName: json['category_name'] as String?,
      categoryNameAm: json['category_name_am'] as String?,
      title: json['title'] as String,
      amount: Money.fromJson((json['amount'] as Map).cast<String, Object?>()),
      anchorCalendar: CalendarKind.parse(json['anchor_calendar'] as String),
      startPeriod: periodFromJson((json['start_period'] as Map).cast<String, Object?>()),
      endPeriod: end is Map ? periodFromJson(end.cast<String, Object?>()) : null,
      dueDay: (json['due_day'] as num).toInt(),
      note: json['note'] as String?,
      isPaused: json['is_paused'] as bool,
    );
  }
}

class OccurrenceDto {
  const OccurrenceDto({
    required this.fixedExpenseId,
    required this.categoryId,
    required this.categoryName,
    required this.categoryNameAm,
    required this.title,
    required this.period,
    required this.dueDate,
    required this.amount,
    required this.isSettled,
    required this.settledOn,
  });

  final String fixedExpenseId;
  final String categoryId;
  final String? categoryName;
  final String? categoryNameAm;
  final String title;

  /// The anchor Period this occurrence is filed under — send it back to settle or unsettle.
  final Period period;
  final SpendDateDto dueDate;

  /// What was paid when settled, otherwise what is committed.
  final Money amount;
  final bool isSettled;
  final SpendDateDto? settledOn;

  factory OccurrenceDto.fromJson(Map<String, Object?> json) {
    final settledOn = json['settled_on'];
    return OccurrenceDto(
      fixedExpenseId: json['fixed_expense_id'] as String,
      categoryId: json['category_id'] as String,
      categoryName: json['category_name'] as String?,
      categoryNameAm: json['category_name_am'] as String?,
      title: json['title'] as String,
      period: periodFromJson((json['period'] as Map).cast<String, Object?>()),
      dueDate: SpendDateDto.fromJson((json['due_date'] as Map).cast<String, Object?>()),
      amount: Money.fromJson((json['amount'] as Map).cast<String, Object?>()),
      isSettled: json['is_settled'] as bool,
      settledOn:
          settledOn is Map ? SpendDateDto.fromJson(settledOn.cast<String, Object?>()) : null,
    );
  }
}

class OccurrenceMonthDto {
  const OccurrenceMonthDto({
    required this.occurrences,
    required this.committed,
    required this.settled,
    required this.outstanding,
  });

  /// Soonest due first.
  final List<OccurrenceDto> occurrences;
  final Money committed;
  final Money settled;
  final Money outstanding;

  factory OccurrenceMonthDto.fromJson(Map<String, Object?> json) => OccurrenceMonthDto(
        occurrences: (json['occurrences'] as List)
            .map((o) => OccurrenceDto.fromJson((o as Map).cast<String, Object?>()))
            .toList(),
        committed: Money.fromJson((json['committed'] as Map).cast<String, Object?>()),
        settled: Money.fromJson((json['settled'] as Map).cast<String, Object?>()),
        outstanding: Money.fromJson((json['outstanding'] as Map).cast<String, Object?>()),
      );
}

class FixedExpensesApi {
  FixedExpensesApi(this._client);

  final ApiClient _client;

  static const _base = '/api/fixed-expenses';

  Future<List<FixedExpenseDto>> list() async {
    final data = await _client.get(_base);
    return (data as List)
        .map((c) => FixedExpenseDto.fromJson((c as Map).cast<String, Object?>()))
        .toList();
  }

  Future<FixedExpenseDto> schedule({
    required String categoryId,
    required String title,
    required int amountMinor,
    required Period startPeriod,
    Period? endPeriod,
    int dueDay = 1,
    String? note,
  }) async {
    final data = await _client.post(_base, body: {
      'category_id': categoryId,
      'title': title,
      'amount_minor': amountMinor,
      'start_period': periodToJson(startPeriod),
      if (endPeriod != null) 'end_period': periodToJson(endPeriod),
      'due_day': dueDay,
      if (note != null) 'note': note,
    });
    return FixedExpenseDto.fromJson((data as Map).cast<String, Object?>());
  }

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
    final data = await _client.patch('$_base/$id', body: {
      if (title != null) 'title': title,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (categoryId != null) 'category_id': categoryId,
      if (dueDay != null) 'due_day': dueDay,
      if (note != null) 'note': note,
      if (endPeriod != null) 'end_period': periodToJson(endPeriod),
      if (clearEndPeriod) 'clear_end_period': true,
    });
    return FixedExpenseDto.fromJson((data as Map).cast<String, Object?>());
  }

  Future<void> delete(String id) => _client.delete('$_base/$id');

  Future<FixedExpenseDto> pause(String id) async {
    final data = await _client.post('$_base/$id/pause');
    return FixedExpenseDto.fromJson((data as Map).cast<String, Object?>());
  }

  Future<FixedExpenseDto> resume(String id) async {
    final data = await _client.post('$_base/$id/resume');
    return FixedExpenseDto.fromJson((data as Map).cast<String, Object?>());
  }

  /// Everything owed in [period], in the calendar the user is viewing.
  Future<OccurrenceMonthDto> occurrences(Period period) async {
    final data = await _client.get('$_base/occurrences', query: {
      'period_year': period.year,
      'period_month': period.month,
      'period_calendar': period.calendar.wire,
    });
    return OccurrenceMonthDto.fromJson((data as Map).cast<String, Object?>());
  }

  /// Mark [period] paid. [amountMinor] defaults to the committed amount; [settledOn] (a Gregorian
  /// `YYYY-MM-DD`) defaults to today on the server.
  Future<OccurrenceDto> settle(
    String id,
    Period period, {
    int? amountMinor,
    String? settledOn,
  }) async {
    final data = await _client.post('$_base/$id/settlements', body: {
      'period': periodToJson(period),
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (settledOn != null) 'settled_on': {'calendar': 'gregorian', 'value': settledOn},
    });
    return OccurrenceDto.fromJson((data as Map).cast<String, Object?>());
  }

  /// Undo a recorded payment.
  Future<OccurrenceDto> unsettle(String id, Period period) async {
    final data = await _client.delete(
      '$_base/$id/settlements?period_year=${period.year}&period_month=${period.month}'
      '&period_calendar=${period.calendar.wire}',
    );
    return OccurrenceDto.fromJson((data as Map).cast<String, Object?>());
  }
}
