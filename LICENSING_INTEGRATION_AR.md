# TVEXP Licensing integration

## What changed
- Added a subscription-code screen before Xtream login.
- Added `LicenseService` calling the deployed Cloudflare Worker:
  `https://tvexp-licensing-api.waamali11286.workers.dev`
- Stores the 12-digit subscription code and a random per-installation device identifier using `flutter_secure_storage`.
- Validates the subscription with the server at app startup and again before video playback and download actions.
- Protects online and offline playback through the `PlayerScreen` validation.
- Protects internal and external download initiation, series episode playback/download, and resuming paused internal downloads.
- Bumped app version to `2.3.4+15`.

## Server endpoints used
- `POST /activate` with `{ "code": "12 digits", "deviceId": "stable installation id" }`
- `POST /validate` with the same fields

The server remains authoritative for activation, device binding, revocation, and expiry.

## Important behavior
- Validation fails closed when the server cannot be reached. The app does not provide an offline subscription bypass.
- The device identifier is a random ID stored in Android secure storage. It is stable for that app installation, not a hardware serial number. Clearing app data/reinstalling may create a new identifier, and the server will reject it if the code is already bound to the previous identifier. Support/admin reset would be needed for legitimate device recovery.
- Mobile and Android TV use separate Android application IDs, so each installation has its own secure storage and device identifier.
- The client-side checks are an app access gate. They do not proxy the actual IPTV stream/download through the licensing server; a modified client could bypass client-side checks. For stronger anti-tamper enforcement, stream/download authorization must also be enforced by a controlled backend or provider.

## Build and verification
This environment did not have Flutter/Dart installed, so `flutter pub get`, `dart format`, `flutter analyze`, tests, and APK/AAB builds were not run. Run these in the Flutter project environment before publishing:
1. `flutter pub get`
2. `dart format lib`
3. `flutter analyze`
4. `flutter test`
5. Build Mobile and TV release flavors and test on both Android phone and Android TV.

## Signing key safety
The uploaded archive contained `android/app/tvexp-release-key.jks`. It has been excluded from this modified delivery to avoid redistributing a private signing key. Keep the original signing key in secure offline storage and use the configured GitHub Actions signing secrets for releases. Do not commit JKS/keystore files or passwords to GitHub.
