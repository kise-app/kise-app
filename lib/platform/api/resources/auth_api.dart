/// Auth data source: register, login, and the signed-in profile.
///
/// DTOs are the wire shape, and they never leave `infrastructure/` — a screen sees a domain type,
/// mapped from these. Here they are kept deliberately small: enough to round-trip the API's JSON and
/// hand back typed values. The data source owns the token side effect: on register and login it
/// writes the returned token to the [AuthTokenStore], so a subsequent request is authenticated with
/// no extra step.
library;

import '../api_client.dart';
import '../auth_token_store.dart';

/// The account's plan. [effective] is what is in force now: an ended trial is `basic`.
/// The account's plan. Admins add plans, so [effective] is not limited to `trial`, `basic` and
/// `pro`; [name] is what to show. `trial` and `basic` are built in and keep their meaning.
class PlanDto {
  const PlanDto({
    this.plan = 'basic',
    this.effective = 'basic',
    this.name = '',
    this.expiresAt,
    this.daysLeft,
    this.aiEnabled = false,
    this.receiptsPerMonth = 0,
    this.voicePerMonth = 0,
  });

  final String plan;
  final String effective;

  /// The plan's name as an admin wrote it; empty from an older server.
  final String name;
  final String? expiresAt;
  final int? daysLeft;

  /// Any part of the assistant: typed requests, receipt scans or voice notes.
  final bool aiEnabled;

  /// A month; null is no monthly limit.
  final int? receiptsPerMonth;
  final int? voicePerMonth;

  bool get isTrial => effective == 'trial';
  bool get isBasic => effective == 'basic';

  factory PlanDto.fromJson(Map<String, Object?> json) {
    final ai = (json['ai_enabled'] as bool?) ?? false;
    // An older server sends no limits: read them from ai_enabled, as it meant then.
    int? monthly(String key) =>
        json.containsKey(key) ? (json[key] as num?)?.toInt() : (ai ? null : 0);
    return PlanDto(
      plan: (json['plan'] as String?) ?? 'basic',
      effective: (json['effective'] as String?) ?? 'basic',
      name: (json['name'] as String?) ?? '',
      expiresAt: json['expires_at'] as String?,
      daysLeft: (json['days_left'] as num?)?.toInt(),
      aiEnabled: ai,
      receiptsPerMonth: monthly('receipts_per_month'),
      voicePerMonth: monthly('voice_per_month'),
    );
  }
}

class ProfileDto {
  const ProfileDto({
    required this.id,
    required this.email,
    required this.displayName,
    required this.calendar,
    required this.language,
    required this.currency,
    required this.registeredAt,
    this.plan = const PlanDto(),
  });

  final String id;
  final String email;
  final String displayName;
  final String calendar;
  final String language;
  final String currency;
  final String registeredAt;
  final PlanDto plan;

  factory ProfileDto.fromJson(Map<String, Object?> json) => ProfileDto(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['display_name'] as String,
    calendar: json['calendar'] as String,
    language: json['language'] as String,
    currency: json['currency'] as String,
    registeredAt: json['registered_at'] as String,
    plan: json['plan'] is Map
        ? PlanDto.fromJson((json['plan'] as Map).cast<String, Object?>())
        : const PlanDto(),
  );
}

class AuthResultDto {
  const AuthResultDto({
    required this.token,
    required this.expiresAt,
    required this.owner,
    this.created = false,
  });

  final String token;
  final String expiresAt;
  final ProfileDto owner;

  /// True when this sign-in made the account (social sign-in can do either).
  final bool created;

  factory AuthResultDto.fromJson(Map<String, Object?> json) => AuthResultDto(
    token: json['token'] as String,
    expiresAt: json['expires_at'] as String,
    owner: ProfileDto.fromJson((json['owner'] as Map).cast<String, Object?>()),
    created: (json['created'] as bool?) ?? false,
  );
}

/// Which sign-in methods the server has set up. Email and password is always on.
class SignInProvidersDto {
  const SignInProvidersDto({this.google = false, this.apple = false, this.facebook = false});

  final bool google;
  final bool apple;
  final bool facebook;

  factory SignInProvidersDto.fromJson(Map<String, Object?> json) => SignInProvidersDto(
    google: (json['google'] as bool?) ?? false,
    apple: (json['apple'] as bool?) ?? false,
    facebook: (json['facebook'] as bool?) ?? false,
  );
}

class AuthApi {
  AuthApi(this._client, this._tokenStore);

  final ApiClient _client;
  final AuthTokenStore _tokenStore;

  Future<AuthResultDto> register({
    required String email,
    required String password,
    required String displayName,
    String? calendar,
    String? language,
    String? currency,
  }) async {
    final data = await _client.post(
      '/api/auth/register',
      body: {
        'email': email,
        'password': password,
        'display_name': displayName,
        if (calendar != null) 'calendar': calendar,
        if (language != null) 'language': language,
        if (currency != null) 'currency': currency,
      },
    );
    final result = AuthResultDto.fromJson((data as Map).cast<String, Object?>());
    await _tokenStore.write(result.token);
    return result;
  }

  Future<AuthResultDto> login({required String email, required String password}) async {
    final data = await _client.post(
      '/api/auth/login',
      body: {'email': email, 'password': password},
    );
    final result = AuthResultDto.fromJson((data as Map).cast<String, Object?>());
    await _tokenStore.write(result.token);
    return result;
  }

  Future<SignInProvidersDto> providers() async {
    final data = await _client.get('/api/auth/providers');
    return SignInProvidersDto.fromJson((data as Map).cast<String, Object?>());
  }

  /// Sign in with a provider's token — Google's ID token, for now. Makes the account the first
  /// time, using the calendar/language/currency given.
  Future<AuthResultDto> social({
    required String provider,
    required String token,
    String? nonce,
    String? displayName,
    String? calendar,
    String? language,
    String? currency,
  }) async {
    final data = await _client.post(
      '/api/auth/social',
      body: {
        'provider': provider,
        'token': token,
        if (nonce != null) 'nonce': nonce,
        if (displayName != null) 'display_name': displayName,
        if (calendar != null) 'calendar': calendar,
        if (language != null) 'language': language,
        if (currency != null) 'currency': currency,
      },
    );
    final result = AuthResultDto.fromJson((data as Map).cast<String, Object?>());
    await _tokenStore.write(result.token);
    return result;
  }

  Future<ProfileDto> me() async {
    final data = await _client.get('/api/auth/me');
    return ProfileDto.fromJson((data as Map).cast<String, Object?>());
  }

  Future<ProfileDto> updateMe({String? displayName, String? calendar, String? language}) async {
    final data = await _client.patch(
      '/api/auth/me',
      body: {
        if (displayName != null) 'display_name': displayName,
        if (calendar != null) 'calendar': calendar,
        if (language != null) 'language': language,
      },
    );
    return ProfileDto.fromJson((data as Map).cast<String, Object?>());
  }

  /// Change the password. A wrong current password is an [ApiException] with code
  /// `current_password_incorrect`.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.post(
      '/api/auth/password',
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  /// Forget the token. The next request goes out unauthenticated.
  Future<void> signOut() => _tokenStore.clear();
}
