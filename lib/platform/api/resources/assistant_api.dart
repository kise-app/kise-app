/// Assistant data source: turn typed text, a voice note or a receipt photo into draft expenses, and
/// answer questions about spending.
///
/// Nothing here records an expense. The server hands back [DraftExpenseDto]s — already checked
/// against the owner's categories and units, with dates resolved in both calendars — and the app
/// records the ones the person confirms through [ExpensesApi.record]. Fixed monthly expenses come
/// back as [FixedDraftDto]s (a new commitment) and [PaymentDraftDto]s ("I paid the rent"), which
/// the app schedules or settles through [FixedExpensesApi].
///
/// Every call sends the phone's date as `today`, because "today" and "yesterday" mean the person's
/// day, not the server's (which runs on UTC).
library;

import '../../../shared_kernel/money.dart';
import '../../../shared_kernel/period.dart';
import '../api_client.dart';
import 'expenses_api.dart';
import 'fixed_expenses_api.dart' show periodFromJson;

class AssistantStatusDto {
  const AssistantStatusDto({
    required this.enabled,
    required this.hourlyLimit,
    this.allowed = false,
    this.maxVoiceSeconds = 60,
  });

  /// The server has a model configured.
  final bool enabled;

  /// This account's plan includes the assistant (Pro, or a running trial).
  final bool allowed;
  final int hourlyLimit;

  /// The longest voice note this plan accepts. Recording stops here and what was said is sent.
  final int maxVoiceSeconds;

  Duration get maxVoiceNote => Duration(seconds: maxVoiceSeconds);

  factory AssistantStatusDto.fromJson(Map<String, Object?> json) => AssistantStatusDto(
    enabled: json['enabled'] as bool,
    allowed: (json['allowed'] as bool?) ?? false,
    hourlyLimit: (json['hourly_limit'] as num).toInt(),
    maxVoiceSeconds: (json['max_voice_seconds'] as num?)?.toInt() ?? 60,
  );
}

class DraftItemDto {
  const DraftItemDto({
    required this.itemName,
    required this.quantity,
    required this.unitId,
    required this.unitCode,
  });

  final String itemName;
  final String quantity;
  final String unitId;
  final String unitCode;

  factory DraftItemDto.fromJson(Map<String, Object?> json) => DraftItemDto(
    itemName: json['item_name'] as String,
    quantity: json['quantity'] as String,
    unitId: json['unit_id'] as String,
    unitCode: json['unit_code'] as String,
  );
}

class DraftExpenseDto {
  const DraftExpenseDto({
    required this.categoryId,
    required this.categoryName,
    required this.categoryNameAm,
    required this.amount,
    required this.spentOn,
    required this.paymentMethod,
    required this.note,
    required this.item,
    required this.warnings,
    this.newCategory,
  });

  final String categoryId;
  final String categoryName;
  final String? categoryNameAm;

  /// A category the assistant suggests creating because none of the person's fits. Until it is
  /// created the draft is filed under [categoryId] (the closest, or Other).
  final String? newCategory;
  final Money amount;
  final SpendDateDto spentOn;
  final String paymentMethod;
  final String? note;
  final DraftItemDto? item;

  /// `date_unclear`, `date_in_future`, `date_long_ago`, `category_guessed`: what to double-check.
  final List<String> warnings;

  factory DraftExpenseDto.fromJson(Map<String, Object?> json) {
    final item = json['item'];
    return DraftExpenseDto(
      categoryId: json['category_id'] as String,
      categoryName: json['category_name'] as String,
      categoryNameAm: json['category_name_am'] as String?,
      amount: Money.fromJson((json['amount'] as Map).cast<String, Object?>()),
      spentOn: SpendDateDto.fromJson((json['spent_on'] as Map).cast<String, Object?>()),
      paymentMethod: json['payment_method'] as String,
      note: json['note'] as String?,
      item: item is Map ? DraftItemDto.fromJson(item.cast<String, Object?>()) : null,
      warnings: ((json['warnings'] as List?) ?? const []).cast<String>(),
      newCategory: json['new_category'] as String?,
    );
  }
}

/// A new monthly commitment the person described: "rent 8,000 every month on the 5th".
class FixedDraftDto {
  const FixedDraftDto({
    required this.title,
    required this.categoryId,
    required this.categoryName,
    required this.categoryNameAm,
    required this.amount,
    required this.dueDay,
    required this.startPeriod,
    required this.note,
    required this.warnings,
    this.newCategory,
  });

  final String title;
  final String categoryId;

  /// As on [DraftExpenseDto]: a category the assistant suggests creating.
  final String? newCategory;
  final String categoryName;
  final String? categoryNameAm;
  final Money amount;
  final int dueDay;
  final Period startPeriod;
  final String? note;
  final List<String> warnings;

  factory FixedDraftDto.fromJson(Map<String, Object?> json) => FixedDraftDto(
    title: json['title'] as String,
    categoryId: json['category_id'] as String,
    categoryName: json['category_name'] as String,
    categoryNameAm: json['category_name_am'] as String?,
    amount: Money.fromJson((json['amount'] as Map).cast<String, Object?>()),
    dueDay: (json['due_day'] as num).toInt(),
    startPeriod: periodFromJson((json['start_period'] as Map).cast<String, Object?>()),
    note: json['note'] as String?,
    warnings: ((json['warnings'] as List?) ?? const []).cast<String>(),
    newCategory: json['new_category'] as String?,
  );
}

/// "I paid the rent": one existing commitment, to be marked paid for [period].
class PaymentDraftDto {
  const PaymentDraftDto({
    required this.fixedExpenseId,
    required this.title,
    required this.period,
    required this.amount,
    required this.paidOn,
    required this.warnings,
  });

  final String fixedExpenseId;
  final String title;

  /// The commitment's own Period — sent back to settle.
  final Period period;
  final Money amount;
  final SpendDateDto paidOn;

  /// `already_paid` when this month was already marked paid.
  final List<String> warnings;

  factory PaymentDraftDto.fromJson(Map<String, Object?> json) => PaymentDraftDto(
    fixedExpenseId: json['fixed_expense_id'] as String,
    title: json['title'] as String,
    period: periodFromJson((json['period'] as Map).cast<String, Object?>()),
    amount: Money.fromJson((json['amount'] as Map).cast<String, Object?>()),
    paidOn: SpendDateDto.fromJson((json['paid_on'] as Map).cast<String, Object?>()),
    warnings: ((json['warnings'] as List?) ?? const []).cast<String>(),
  );
}

/// An answer to a question; [transcript] is what was heard when it was asked out loud.
class AnswerDto {
  const AnswerDto({required this.answer, this.transcript});

  final String answer;
  final String? transcript;
}

class DraftReplyDto {
  const DraftReplyDto({
    required this.message,
    required this.transcript,
    required this.merchant,
    required this.drafts,
    this.fixedDrafts = const [],
    this.paymentDrafts = const [],
  });

  /// One sentence from the assistant, in the person's language.
  final String message;

  /// What was heard, for a voice note.
  final String? transcript;

  /// The shop, for a receipt.
  final String? merchant;
  final List<DraftExpenseDto> drafts;

  /// New monthly commitments ("rent every month").
  final List<FixedDraftDto> fixedDrafts;

  /// Existing commitments said to be paid ("I paid the rent").
  final List<PaymentDraftDto> paymentDrafts;

  bool get isEmpty => drafts.isEmpty && fixedDrafts.isEmpty && paymentDrafts.isEmpty;

  static List<T> _list<T>(Object? raw, T Function(Map<String, Object?>) parse) =>
      ((raw as List?) ?? const []).map((d) => parse((d as Map).cast<String, Object?>())).toList();

  factory DraftReplyDto.fromJson(Map<String, Object?> json) => DraftReplyDto(
    message: (json['message'] as String?) ?? '',
    transcript: json['transcript'] as String?,
    merchant: json['merchant'] as String?,
    drafts: _list(json['drafts'], DraftExpenseDto.fromJson),
    fixedDrafts: _list(json['fixed_drafts'], FixedDraftDto.fromJson),
    paymentDrafts: _list(json['payment_drafts'], PaymentDraftDto.fromJson),
  );
}

class AssistantApi {
  AssistantApi(this._client);

  final ApiClient _client;

  static const _base = '/api/assistant';

  Future<AssistantStatusDto> status() async {
    final data = await _client.get('$_base/status');
    return AssistantStatusDto.fromJson((data as Map).cast<String, Object?>());
  }

  Future<DraftReplyDto> readText(String text, {required String today}) async {
    final data = await _client.postSlow('$_base/text', body: {'text': text, 'today': today});
    return DraftReplyDto.fromJson((data as Map).cast<String, Object?>());
  }

  Future<DraftReplyDto> readVoice(
    List<int> bytes, {
    required String contentType,
    required String today,
    String filename = 'voice.m4a',
  }) async {
    final data = await _client.postMultipart(
      '$_base/voice',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      fields: {'today': today},
    );
    return DraftReplyDto.fromJson((data as Map).cast<String, Object?>());
  }

  Future<DraftReplyDto> readReceipt(
    List<int> bytes, {
    required String contentType,
    required String today,
    String filename = 'receipt.jpg',
  }) async {
    final data = await _client.postMultipart(
      '$_base/receipt',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      fields: {'today': today},
    );
    return DraftReplyDto.fromJson((data as Map).cast<String, Object?>());
  }

  Future<String> ask(String question, {required String today}) async {
    final data = await _client.postSlow('$_base/ask', body: {'question': question, 'today': today});
    return ((data as Map)['answer'] as String?) ?? '';
  }

  /// A question asked out loud: transcribed and answered in one call.
  Future<AnswerDto> askVoice(
    List<int> bytes, {
    required String contentType,
    required String today,
    String filename = 'question.m4a',
  }) async {
    final data = await _client.postMultipart(
      '$_base/ask/voice',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      fields: {'today': today},
    );
    final map = (data as Map).cast<String, Object?>();
    return AnswerDto(
      answer: (map['answer'] as String?) ?? '',
      transcript: map['transcript'] as String?,
    );
  }
}
