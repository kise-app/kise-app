/// The Google button on the sign-in screen: shown only when the server and this build are both set
/// up for it, and a successful Google sign-in hands the ID token to the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kise/features/auth/presentation/sign_in_screen.dart';
import 'package:kise/features/auth/social_sign_in.dart';
import 'package:kise/platform/api/api.dart';
import 'package:kise/platform/session/session_controller.dart';
import 'package:kise/platform/settings.dart';
import 'package:kise/platform/theme.dart';
import 'package:kise/shared_kernel/period.dart';

import '../support/fake_api.dart';

class FakeSocialAuth implements SocialAuth {
  FakeSocialAuth({this.configured = true, this.cancel = false, this.fail = false});

  final bool configured;
  final bool cancel;
  final bool fail;
  int calls = 0;

  @override
  bool get googleConfigured => configured;

  @override
  Future<SocialCredential> google() async {
    calls++;
    if (cancel) throw const SocialSignInCancelled();
    if (fail) throw Exception('plugin blew up');
    return const SocialCredential(token: 'google-id-token', displayName: 'Abebe');
  }

  @override
  Future<void> signOut() async {}
}

Widget _host({required FakeAuthApi auth, required FakeSocialAuth social}) => ProviderScope(
  overrides: [
    settingsStoreProvider.overrideWithValue(
      InMemorySettingsStore(
        const AppSettings(language: Language.english, calendar: CalendarKind.gregorian),
      ),
    ),
    authTokenStoreProvider.overrideWithValue(InMemoryAuthTokenStore()),
    authApiProvider.overrideWithValue(auth),
    socialAuthProvider.overrideWithValue(social),
  ],
  child: MaterialApp(theme: buildTheme(), home: const SignInScreen()),
);

const _googleOn = SignInProvidersDto(google: true);

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 2600);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('hidden when the server has Google off', (tester) async {
    await tester.pumpWidget(_host(auth: FakeAuthApi(), social: FakeSocialAuth()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signin-google')), findsNothing);
  });

  testWidgets('hidden when this build has no Google client id', (tester) async {
    await tester.pumpWidget(
      _host(
        auth: FakeAuthApi(signInProviders: _googleOn),
        social: FakeSocialAuth(configured: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signin-google')), findsNothing);
  });

  testWidgets('signs in with the Google ID token and the device preferences', (tester) async {
    final auth = FakeAuthApi(signInProviders: _googleOn);
    late ProviderContainer container;
    await tester.pumpWidget(_host(auth: auth, social: FakeSocialAuth()));
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(tester.element(find.byType(SignInScreen)));

    await tester.tap(find.byKey(const Key('signin-google')));
    await tester.pumpAndSettle();

    expect(auth.socialCalls.single, {
      'provider': 'google',
      'token': 'google-id-token',
      'display_name': 'Abebe',
      'calendar': 'gregorian',
      'language': 'en',
      'currency': 'ETB',
    });
    expect(container.read(sessionProvider).valueOrNull, isA<SignedIn>());
  });

  testWidgets('closing the Google sheet is not an error', (tester) async {
    final auth = FakeAuthApi(signInProviders: _googleOn);
    await tester.pumpWidget(_host(auth: auth, social: FakeSocialAuth(cancel: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signin-google')));
    await tester.pumpAndSettle();
    expect(auth.socialCalls, isEmpty);
    expect(find.byKey(const Key('signin-social-error')), findsNothing);
  });

  testWidgets('a plugin failure says so', (tester) async {
    await tester.pumpWidget(
      _host(
        auth: FakeAuthApi(signInProviders: _googleOn),
        social: FakeSocialAuth(fail: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signin-google')));
    await tester.pumpAndSettle();
    expect(find.text('Google sign-in did not work. Try again.'), findsOneWidget);
  });

  testWidgets('an existing password account is explained', (tester) async {
    final auth = FakeAuthApi(
      signInProviders: _googleOn,
      socialError: const ApiException(
        message: 'An account with this email already exists. Sign in with your password.',
        code: 'sign_in_with_password',
        statusCode: 409,
      ),
    );
    await tester.pumpWidget(_host(auth: auth, social: FakeSocialAuth()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signin-google')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sign in with your password'), findsOneWidget);
  });
}
