/// Keeps the on-device settings and the server profile in agreement.
///
/// The server owns the profile — display name, calendar, language and the account currency — so a
/// reinstall or a second phone shows the same thing. Two directions:
///
/// * **Down**, on sign-in and at boot: [ProfileSync.apply] copies the profile into [AppSettings].
///   Theme and palette stay device-local; they are a property of the screen, not the person.
/// * **Up**, whenever the person changes name, calendar or language anywhere in the app (Settings,
///   the dashboard toggles): the change is sent with `PATCH /api/auth/me`. The name is debounced so
///   typing "Selam" is one request, not five.
///
/// The currency is not pushed: the server fixes it at registration because every amount already
/// recorded is written in it.
///
/// Nothing is pushed until a profile has been applied, so a signed-out app (or a test that never
/// signs in) makes no requests.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared_kernel/period.dart';
import '../api/api.dart';
import '../settings.dart';

typedef _Synced = ({String name, CalendarKind calendar, Language language});

class ProfileSync {
  ProfileSync(this._ref);

  final Ref _ref;
  _Synced? _synced;
  Timer? _nameTimer;

  static const nameDebounce = Duration(milliseconds: 800);

  /// Server -> device.
  void apply(ProfileDto profile) {
    final calendar = _parse(CalendarKind.parse, profile.calendar, CalendarKind.ethiopian);
    final language = _parse(Language.parse, profile.language, Language.amharic);
    // Recorded first, so the settings change below is recognised as already in sync.
    _synced = (name: profile.displayName.trim(), calendar: calendar, language: language);
    _ref
        .read(settingsProvider.notifier)
        .applyProfile(
          ownerName: profile.displayName.trim(),
          calendar: calendar,
          language: language,
          currency: profile.currency,
        );
  }

  /// Forget the profile on sign-out, so nothing is pushed for an account that is not there.
  void reset() {
    _nameTimer?.cancel();
    _synced = null;
  }

  /// Device -> server. Called for every settings change.
  void onSettingsChanged(AppSettings next) {
    final synced = _synced;
    if (synced == null) return;
    if (next.calendar != synced.calendar || next.language != synced.language) {
      _push(calendar: next.calendar, language: next.language);
    }
    if (next.ownerName.trim() != synced.name && next.ownerName.trim().isNotEmpty) {
      _nameTimer?.cancel();
      _nameTimer = Timer(nameDebounce, () => _push(name: next.ownerName.trim()));
    }
  }

  Future<void> _push({String? name, CalendarKind? calendar, Language? language}) async {
    final before = _synced;
    if (before == null) return;
    try {
      final profile = await _ref
          .read(authApiProvider)
          .updateMe(displayName: name, calendar: calendar?.wire, language: language?.wire);
      if (_synced == null) return; // signed out meanwhile
      _synced = (
        name: profile.displayName.trim(),
        calendar: _parse(CalendarKind.parse, profile.calendar, before.calendar),
        language: _parse(Language.parse, profile.language, before.language),
      );
    } on ApiException {
      // The device keeps the change; the next change (or the next sign-in) tries again.
    }
  }

  void dispose() => _nameTimer?.cancel();

  static T _parse<T>(T Function(String) parse, String value, T fallback) {
    try {
      return parse(value);
    } on ArgumentError {
      return fallback;
    }
  }
}

final profileSyncProvider = Provider<ProfileSync>((ref) {
  final sync = ProfileSync(ref);
  ref.listen<AppSettings>(settingsProvider, (_, next) => sync.onSettingsChanged(next));
  ref.onDispose(sync.dispose);
  return sync;
});
