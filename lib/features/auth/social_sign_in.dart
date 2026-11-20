/// Social sign-in on the phone: get a token from the provider, hand it to the server.
///
/// The server does the verifying (see the backend's `identity/infrastructure/social.py`); the app
/// only runs the provider's own sign-in sheet and passes the result on. Behind a [SocialAuth]
/// interface so widget tests need no plugin.
///
/// Google needs two OAuth client ids, passed at build time in `env/*.json`:
///
/// * `GOOGLE_IOS_CLIENT_ID` — the iOS client (its reversed form is also the URL scheme in
///   `ios/Flutter/Google.xcconfig`);
/// * `GOOGLE_SERVER_CLIENT_ID` — the Web application client the server checks tokens against.
///   Android needs it to get an ID token at all.
///
/// The Google button shows only when the server has Google switched on *and* this build has the
/// id its platform needs, so a half-configured build shows nothing rather than a broken button.
library;

import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../platform/api/api.dart';

const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
const _googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// What a provider handed back: the token for the server, and a name when it gave one.
class SocialCredential {
  const SocialCredential({required this.token, this.displayName, this.nonce});

  final String token;
  final String? displayName;
  final String? nonce;
}

/// Thrown when the person closed the provider's sheet — not an error worth showing.
class SocialSignInCancelled implements Exception {
  const SocialSignInCancelled();
}

abstract class SocialAuth {
  /// Whether this build is configured for Google on this platform.
  bool get googleConfigured;

  /// Run Google's sign-in and return its ID token. Throws [SocialSignInCancelled] if dismissed.
  Future<SocialCredential> google();

  /// Forget the provider session, so the next sign-in can pick another account.
  Future<void> signOut();
}

class PluginSocialAuth implements SocialAuth {
  bool _initialized = false;

  @override
  bool get googleConfigured {
    if (Platform.isIOS || Platform.isMacOS) {
      return _googleIosClientId.isNotEmpty && _googleServerClientId.isNotEmpty;
    }
    return _googleServerClientId.isNotEmpty;
  }

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: (Platform.isIOS || Platform.isMacOS) ? _googleIosClientId : null,
      serverClientId: _googleServerClientId,
    );
    _initialized = true;
  }

  @override
  Future<SocialCredential> google() async {
    await _init();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) throw const SocialSignInCancelled();
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const ApiException(message: 'Google did not return a sign-in token');
    }
    return SocialCredential(token: idToken, displayName: account.displayName);
  }

  @override
  Future<void> signOut() async {
    if (!_initialized) return;
    await GoogleSignIn.instance.signOut();
  }
}

final socialAuthProvider = Provider<SocialAuth>((ref) => PluginSocialAuth());

/// The server's providers. A failure reads as "none", so the sign-in screen just shows email.
final signInProvidersProvider = FutureProvider<SignInProvidersDto>((ref) async {
  try {
    return await ref.watch(authApiProvider).providers();
  } on ApiException {
    return const SignInProvidersDto();
  }
});
