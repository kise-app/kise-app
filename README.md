# Kise — Flutter app

The iOS and Android client. The FastAPI backend lives in a separate repository: **kise-backend**.

```bash
flutter pub get
flutter analyze
flutter test                        # 60 tests
flutter run -d "iPhone 16 Pro"      # or: flutter run -d chrome
flutter run --release               # profile-free build, for timing the real thing
```

`make help` lists shortcuts for the same things. The two that matter day to day: `make sim` (iOS
Simulator against a backend on `localhost`) and `make iphone` (the physical phone, pointed at the
Mac's LAN IP via `env/dev.json`). Add `MODE=release` to either.

Android works the same way: `make android` (the phone against the Mac's backend), `make
android-prod` (against the deployed backend) and `make android-install` (a release APK against the
deployed backend, installed to stay, like `make iphone-install`). They pick the first Android device
attached; `ANDROID=<id>` chooses another (`make devices` lists them). Once: install Android Studio
so the SDK is there, run `flutter doctor --android-licenses`, and on the phone turn on Developer
options > USB debugging (tap Build number 7 times to reveal Developer options).

## Layout

```
lib/
├── shared_kernel/   ethiopian_date · period · money — ports of the backend's value objects
├── platform/        settings (+ persistence), theme
├── features/
│   ├── dashboard/   the month view; widgets/ holds its sections
│   └── settings/    name, calendar, language, currency, budget
├── shared/widgets/  period navigator, option cards, reveal animation
└── app_shell.dart   bottom navigation
```

`shared_kernel/` is a deliberate duplicate of the backend's calendar and money logic, so the app can
label and pick Ethiopian dates with no round trip. `test/shared_kernel/ethiopian_date_test.dart`
asserts the **same anchor dates** as `backend/tests/unit/test_ethiopian_calendar.py`; if either
implementation drifts, one of the two suites fails.

## Notes

- The dashboard reads `GET /api/reports/summary` for the month in view; the Fixed tab reads
  `/api/fixed-expenses`. Month-keyed providers live in `shared/month_data.dart`, and anything that
  writes calls `invalidateMonthData` so every tab refreshes together.
- The server owns the profile (name, calendar, language, currency) and budgets. `ProfileSync`
  (`platform/session/profile_sync.dart`) copies the profile down at sign-in and pushes name,
  calendar and language changes back. Theme stays on the device.
- `todayProvider` is the single source of "now" — nothing else calls `DateTime.now()`, so tests can
  pin the date and every derived value follows.
- Amharic renders from system fonts on iOS. Android coverage of Ethiopic is inconsistent, so a
  bundled Noto Sans Ethiopic is still needed before trusting an Android build.
