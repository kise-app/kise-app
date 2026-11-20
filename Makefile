# Kise mobile app — common tasks.
#
# Day to day:
#   make devices                 what's plugged in / bootable
#   make sim                     iOS Simulator, talking to a backend on localhost
#   make iphone                  the physical iPhone, talking to the Mac's LAN IP
#   make android                 the Android phone (USB or wireless debugging), same LAN backend
#   make android-install         a standalone release build on the Android phone, pointed at prod
#
# Overrides (all optional):
#   IPHONE="endalk’s iPhone"     physical device name or UDID
#   SIM="iPhone 16"              simulator name
#   ANDROID=R5CT1234ABC          Android device id (default: the first Android device attached)
#   PORT=8000                    local backend port
#   IP=192.168.1.4               LAN IP, if auto-detection picks the wrong interface
#   MODE=release                 debug (default) | profile | release

.DEFAULT_GOAL := help

IPHONE ?= endalk’s iPhone
SIM    ?= iPhone 16 Pro
PORT   ?= $(or $(port),8000)
IP     ?= $(ip)
MODE   ?= debug
# The first attached Android device (phone or emulator), unless ANDROID= names one. Looked up only
# when an android target needs it, and then once (`flutter devices` takes a few seconds).
FIRST_ANDROID = $(shell flutter devices --machine 2>/dev/null | python3 tool/first_android_device.py)
ANDROID ?= $(eval ANDROID := $(FIRST_ANDROID))$(ANDROID)
APK      := build/app/outputs/flutter-apk/app-release.apk

DEV_ENV   := env/dev.json
PROD_ENV  := env/prod.json
RUN       := flutter run --$(MODE)
# The simulator shares the Mac's network stack, so localhost reaches a local backend directly.
SIM_API   ?= http://localhost:$(PORT)

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: devices
devices: ## List attached devices and simulators
	@flutter devices
	@echo
	@xcrun simctl list devices available 2>/dev/null | sed -n '/-- iOS/,/^--/p' || true

.PHONY: sim
sim: ## Run on the iOS Simulator (make sim SIM="iPhone 16")
	@xcrun simctl boot "$(SIM)" >/dev/null 2>&1 || true
	@open -a Simulator
	$(RUN) -d "$(SIM)" --dart-define=API_URL=$(SIM_API)

.PHONY: run-ios
run-ios: sim ## Alias for `make sim`

.PHONY: iphone
iphone: $(DEV_ENV) ## Run on the physical iPhone over Wi-Fi (needs env/dev.json; see `make env`)
	$(RUN) -d "$(IPHONE)" --dart-define-from-file=$(DEV_ENV)

.PHONY: iphone-prod
iphone-prod: ## Run on the physical iPhone against the deployed backend
	$(RUN) -d "$(IPHONE)" --dart-define-from-file=$(PROD_ENV)

.PHONY: iphone-install
iphone-install: ## Install a standalone release build on the iPhone, then exit (no attached session)
	# `flutter install` never builds — it ships whatever sits in build/ios/iphoneos, and the copy
	# there is not purged between modes, so a previous `make iphone` leaves Runner.debug.dylib and
	# kernel_blob.bin behind. iOS 14+ refuses to launch a debug build outside Flutter tooling
	# ("debug mode Flutter apps can only be launched from Flutter tooling..."), so wipe first.
	rm -rf build/ios/iphoneos build/ios/Debug-iphoneos
	flutter build ios --release --dart-define-from-file=$(PROD_ENV)
	@test -z "$$(find build/ios/iphoneos/Runner.app \( -name kernel_blob.bin -o -name 'Runner.debug.dylib' \) 2>/dev/null)" \
		|| { echo "Refusing to install: build/ios/iphoneos/Runner.app still has debug artifacts."; exit 1; }
	flutter install --release -d "$(IPHONE)"
	@echo
	@echo "Installed a release build. If the phone says the developer is untrusted, tap through:"
	@echo "  Settings > General > VPN & Device Management > Apple Development: <your Apple ID> > Trust"
	@$(MAKE) --no-print-directory profile-expiry

# -- Android ---------------------------------------------------------------------------
# One-time on the phone: Settings > About phone > tap "Build number" 7 times, then
# Settings > System > Developer options > USB debugging (or Wireless debugging) on.
# On the Mac: the Android SDK (Android Studio, or `brew install --cask android-commandlinetools`),
# then `flutter doctor --android-licenses`.

.PHONY: android-check
android-check:
	@# Only the SDK has to be there. A "license status unknown" warning from flutter doctor is
	@# not fatal: newer sdkmanagers no longer report it, and builds work.
	@flutter doctor -v 2>/dev/null | grep -q 'Android SDK at ' \
		|| { echo "No Android SDK. Install Android Studio (https://developer.android.com/studio),"; \
		     echo "open it once to install the SDK, then run: flutter doctor --android-licenses"; exit 1; }
	@test -n "$(ANDROID)" \
		|| { echo "No Android device found. Plug the phone in (or pair Wireless debugging),"; \
		     echo "allow USB debugging on the phone, then check with: make devices"; exit 1; }

.PHONY: android
android: android-check $(DEV_ENV) ## Run on the Android phone against the Mac's backend (env/dev.json)
	$(RUN) -d "$(ANDROID)" --dart-define-from-file=$(DEV_ENV)

.PHONY: android-prod
android-prod: android-check ## Run on the Android phone against the deployed backend
	$(RUN) -d "$(ANDROID)" --dart-define-from-file=$(PROD_ENV)

.PHONY: android-install
android-install: android-check ## Install a standalone release build on the Android phone (prod)
	flutter build apk --release --dart-define-from-file=$(PROD_ENV)
	flutter install --release -d "$(ANDROID)"
	@echo
	@echo "Installed $(APK) on $(ANDROID). It keeps working after unplugging; no expiry, unlike iOS."
	@echo "To share it: send $(APK) and open it on the phone (allow installs from that app)."

.PHONY: profile-expiry
profile-expiry: ## Show when the free-account signing profile stops launching the app
	@p=$$(ls -t "$$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision \
		"$$HOME/Library/MobileDevice/Provisioning Profiles"/*.mobileprovision 2>/dev/null | head -1); \
	if [ -z "$$p" ]; then echo "No provisioning profile found; open ios/Runner.xcworkspace once."; exit 0; fi; \
	security cms -D -i "$$p" 2>/dev/null | plutil -p - | grep -E '"(Name|ExpirationDate)"'

.PHONY: env
env: ## Write env/dev.json with the Mac's LAN IP (override: make env IP=1.2.3.4 PORT=8000)
	@mkdir -p env
	@ip="$(IP)"; [ -n "$$ip" ] || ip=$$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null); \
	if [ -z "$$ip" ]; then echo "Could not detect a LAN IP; pass one: make env IP=1.2.3.4"; exit 1; fi; \
	printf '{\n  "API_URL": "http://%s:%s"\n}\n' "$$ip" "$(PORT)" > $(DEV_ENV); \
	echo "Wrote $(DEV_ENV) -> http://$$ip:$(PORT)"

# Created on demand, so `make iphone` works on a fresh clone. `make env` refreshes it after the
# Mac's LAN IP changes.
$(DEV_ENV):
	@$(MAKE) --no-print-directory env

.PHONY: get
get: ## flutter pub get
	flutter pub get

.PHONY: test
test: ## Run the Flutter test suite
	flutter test

.PHONY: analyze
analyze: ## flutter analyze
	flutter analyze

.PHONY: run
run: ## Run on any device (make run d="device"); uses env/dev.json if present
	$(RUN) $(if $(d),-d "$(d)",) $(if $(wildcard $(DEV_ENV)),--dart-define-from-file=$(DEV_ENV),)

.PHONY: run-prod
run-prod: ## Run against the deployed backend (env/prod.json); make run-prod d="device"
	$(RUN) $(if $(d),-d "$(d)",) --dart-define-from-file=$(PROD_ENV)

.PHONY: format
format: ## Format Dart sources in place
	dart format lib test

.PHONY: format-check
format-check: ## Verify formatting without writing changes
	dart format --output=none --set-exit-if-changed lib test

.PHONY: clean
clean: ## flutter clean
	flutter clean

.PHONY: check
check: analyze test ## Run analyze + test (CI check)

.PHONY: build-apk
build-apk: ## Build a release APK pointed at production
	flutter build apk --release --dart-define-from-file=$(PROD_ENV)
	@echo "APK: $(APK)"

.PHONY: build-ios
build-ios: ## Build a release iOS app pointed at production
	flutter build ios --release --dart-define-from-file=$(PROD_ENV)
