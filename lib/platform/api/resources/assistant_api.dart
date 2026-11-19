/// Assistant data source: turn typed text, a voice note or a receipt photo into draft expenses, and
/// answer questions about spending.
///
/// Nothing here records an expense. The server hands back [DraftExpenseDto]s — already checked
/// against the owner's categories and units, with dates resolved in both calendars — and the app
/// records the ones the person confirms through [ExpensesApi.record].
///
/// Every call sends the phone's date as `today`, because "today" and "yesterday" mean the person's
/// day, not the server's (which runs on UTC).
library;

import '../../../shared_kernel/money.dart';
import '../api_client.dart';
import 'expenses_api.dart';

class AssistantStatusDto {
  const AssistantStatusDto({required this.enabled, required this.hourlyLimit});

  final bool enabled;
  final int hourlyLimit;

  factory AssistantStatusDto.fromJson(Map<String, Object?> json) => AssistantStatusDto(
    enabled: json['enabled'] as bool,
    hourlyLimit: (json['hourly_limit'] as num).toInt(),
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
  });

  final String categoryId;
  final String categoryName;
  final String? categoryNameAm;
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
    );
  }
}

class DraftReplyDto {
  const DraftReplyDto({
    required this.message,
    required this.transcript,
    required this.merchant,
    required this.drafts,
  });

  /// One sentence from the assistant, in the person's language.
  final String message;

  /// What was heard, for a voice note.
  final String? transcript;

  /// The shop, for a receipt.
  final String? merchant;
  final List<DraftExpenseDto> drafts;

  factory DraftReplyDto.fromJson(Map<String, Object?> json) => DraftReplyDto(
    message: (json['message'] as String?) ?? '',
    transcript: json['transcript'] as String?,
    merchant: json['merchant'] as String?,
    drafts: ((json['drafts'] as List?) ?? const [])
        .map((d) => DraftExpenseDto.fromJson((d as Map).cast<String, Object?>()))
        .toList(),
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
}
