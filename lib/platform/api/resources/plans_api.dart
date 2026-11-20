/// Plans data source: how to pay for Pro.
///
/// Payment is manual for now. The person pays into one of the accounts an admin set in the portal,
/// sends the screenshot on Telegram (or by phone or email) quoting [PaymentInfoDto.reference],
/// and an admin moves them to Pro. The plan itself comes with the profile ([ProfileDto.plan]).
library;

import '../api_client.dart';

class PaymentAccountDto {
  const PaymentAccountDto({required this.bank, required this.holder, required this.number});

  /// A bank, or a mobile wallet such as telebirr.
  final String bank;
  final String holder;
  final String number;

  factory PaymentAccountDto.fromJson(Map<String, Object?> json) => PaymentAccountDto(
    bank: json['bank'] as String,
    holder: json['holder'] as String,
    number: json['number'] as String,
  );
}

/// A plan someone can pay for, and its price as the admin wrote it ("300 birr a month").
class PlanPriceDto {
  const PlanPriceDto({
    required this.plan,
    required this.price,
    required this.aiEnabled,
    this.name = '',
    this.current = false,
    this.typedRequests = false,
    this.receiptsPerMonth = 0,
    this.voicePerMonth = 0,
  });

  /// The plan's code: `basic`, `pro`, or one an admin added.
  final String plan;

  /// Its name as an admin wrote it; empty from an older server.
  final String name;

  /// Empty when the admin has not set one.
  final String price;

  /// Includes any part of the assistant.
  final bool aiEnabled;

  /// The plan this account is on now.
  final bool current;

  /// Typing what was spent, and typed questions.
  final bool typedRequests;

  /// A month; null is no monthly limit, 0 is none.
  final int? receiptsPerMonth;
  final int? voicePerMonth;

  factory PlanPriceDto.fromJson(Map<String, Object?> json) => PlanPriceDto(
    plan: json['plan'] as String,
    name: (json['name'] as String?) ?? '',
    price: (json['price'] as String?) ?? '',
    aiEnabled: (json['ai_enabled'] as bool?) ?? false,
    current: (json['current'] as bool?) ?? false,
    typedRequests: (json['typed_requests'] as bool?) ?? (json['ai_enabled'] as bool? ?? false),
    receiptsPerMonth: _monthly(json, 'receipts_per_month'),
    voicePerMonth: _monthly(json, 'voice_per_month'),
  );

  /// An older server sends no limits: read them from ai_enabled, as it meant then.
  static int? _monthly(Map<String, Object?> json, String key) => json.containsKey(key)
      ? (json[key] as num?)?.toInt()
      : ((json['ai_enabled'] as bool?) ?? false)
      ? null
      : 0;
}

class PaymentInfoDto {
  const PaymentInfoDto({
    required this.ready,
    this.accounts = const [],
    this.plans = const [],
    this.telegram = '',
    this.telegramUrl,
    this.phone = '',
    this.email = '',
    this.note = '',
    this.reference = '',
  });

  /// False until an admin has entered an account and a way to send the screenshot; the app then
  /// only says to contact the Kise team.
  final bool ready;
  final List<PaymentAccountDto> accounts;

  /// Basic, then Pro, each with its price.
  final List<PlanPriceDto> plans;

  /// The price of [plan], or empty.
  String priceOf(String plan) =>
      plans.where((p) => p.plan == plan).map((p) => p.price).firstOrNull ?? '';

  /// A Telegram username, without the @.
  final String telegram;
  final String? telegramUrl;
  final String phone;
  final String email;
  final String note;

  /// What to quote with the screenshot so the admin finds the right account: the person's email.
  final String reference;

  static const notReady = PaymentInfoDto(ready: false);

  factory PaymentInfoDto.fromJson(Map<String, Object?> json) => PaymentInfoDto(
    ready: json['ready'] as bool,
    accounts: [
      for (final account in (json['accounts'] as List? ?? const []))
        PaymentAccountDto.fromJson((account as Map).cast<String, Object?>()),
    ],
    plans: [
      for (final plan in (json['plans'] as List? ?? const []))
        PlanPriceDto.fromJson((plan as Map).cast<String, Object?>()),
    ],
    telegram: (json['telegram'] as String?) ?? '',
    telegramUrl: json['telegram_url'] as String?,
    phone: (json['phone'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    note: (json['note'] as String?) ?? '',
    reference: (json['reference'] as String?) ?? '',
  );
}

class PlansApi {
  PlansApi(this._client);

  final ApiClient _client;

  Future<PaymentInfoDto> payment() async {
    final data = await _client.get('/api/plans/payment');
    return PaymentInfoDto.fromJson((data as Map).cast<String, Object?>());
  }
}
