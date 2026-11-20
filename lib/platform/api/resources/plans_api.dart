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

class PaymentInfoDto {
  const PaymentInfoDto({
    required this.ready,
    this.accounts = const [],
    this.price = '',
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
  final String price;

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
    price: (json['price'] as String?) ?? '',
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
