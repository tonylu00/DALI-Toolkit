# dalimaster

DALI Inspector V2 (cross-platform)

## Supported platforms and key features

- Platforms: Windows, Linux, macOS, Android, iOS, Web (optional/beta)
- Key features:
  - DALI bus inspector, short-address manager, sequence editor, custom keys page
  - Type0 gateway bus-status monitor with in-UI status badge
  - Gateways over BLE, USB serial, TCP/UDP (serial over IP), and Web BLE
  - Built-in mock bus for offline demo and tests
  - Casdoor SSO login with secure token storage and auto refresh
  - Localization (English, Simplified Chinese), theming, analytics, crash reporting

## Getting started

Prerequisites:
- Flutter stable (Dart >= 3.1.4), platform SDKs (Xcode for iOS/macOS, Android SDK/NDK for Android, build tools for desktop targets)

Install dependencies:
```bash
flutter pub get
```

Run on a device:
```bash
flutter devices
flutter run -d <device_id>
```

## Bus status monitor (Type0 gateways)

After a connection is established, `ConnectionManager.ensureGatewayType()` auto-detects the gateway type. When `gatewayType == 0` (Type0), bus monitoring is enabled:
- Receiving two consecutive idle-notification bytes `0xFF 0xFD` marks the bus as abnormal.
- If the sequence isn’t observed again within 5 seconds, the state automatically returns to normal.

The status is displayed in the app bar. Wiring is implemented at the connection layer and UI shell; no extra handling is required by pages.

## Casdoor SSO integration

Dependency: `casdoor_flutter_sdk`.

Configure `lib/auth/casdoor_config.dart` with your Casdoor values (example uses URL scheme `dalitoolkit`; any scheme is fine as long as it matches platform setup):

```
const String kCasdoorClientId = '<YOUR_CLIENT_ID>';
const String kCasdoorServerUrl = 'https://door.casdoor.com';
const String kCasdoorOrganization = '<YOUR_ORG>';
const String kCasdoorAppName = '<YOUR_APP>';
const String kCasdoorRedirectUri = 'dalitoolkit://callback';
```

`kCasdoorRedirectUri` must match the mobile URL scheme/Android intent filter.

### iOS
Add a URL type in `ios/Runner/Info.plist`:
```
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>dalitoolkit</string>
    </array>
  </dict>
  </array>
```

### Android
Add an intent filter under the main activity in `android/app/src/main/AndroidManifest.xml`:
```
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="dalitoolkit" android:host="callback" />
</intent-filter>
```

### Web (optional)
Create `web/callback.html`:
```
<!DOCTYPE html>
<title>Authentication complete</title>
<p>Authentication complete, you can close this window.</p>
<script>
  window.opener.postMessage({'casdoor-auth': window.location.href}, window.location.origin);
  window.close();
</script>
```
Set the redirect URI to your running domain path `/callback` (e.g., `http://localhost:8080/callback`).

### Login flow (via AuthProvider/AuthService)

Use `AuthProvider` to drive the UI. It wraps the full Casdoor flow (authorization UI, code parsing, token exchange, user info, secure persistence). Example (from `lib/pages/login.dart`):

1) Press the login button -> call `context.read<AuthProvider>().login()`
2) On success -> navigate to home via `Navigator.pushNamedAndRemoveUntil('/home', ...)`

No need to call `Casdoor.show()` or `requestOauthAccessToken` directly; those are handled by `AuthService`.

### Auth service (refresh/logout/secure storage)

`lib/auth/auth_service.dart` provides:
- Login -> secure token storage with `flutter_secure_storage`
- Refresh -> auto-refresh on read if expired and a refresh_token is present
- Logout -> `logout(revoke: true)` can call OIDC logout and clears local storage
- User profile -> `getCachedUser()` returns the profile when valid or attempts refresh

Storage format: single key `auth_tokens` (JSON) with accessToken / refreshToken / idToken / expiresAt.

Usage example:
```dart
final auth = AuthService();
final user = await auth.getCachedUser();
if (user == null) {
  final (tokens, profile) = await auth.login();
  print(profile.username);
} else {
  print('Cached user: ${user.username}');
}
```

Notes:
1) iOS Keychain and Android EncryptedSharedPreferences are abstracted by flutter_secure_storage
2) For multi-tenant/multi-account, add a prefix to the key
3) Production tips:
   - Ensure device hardware encryption (Android API >= 23 is default)
   - Call `getCachedUser()` early to trigger silent refresh when needed
4) If your server doesn’t return a refresh_token, consider shorter sessions or re-login prompts

## Localization and multi-platform build

Localization:
- Languages: English (`en`), Simplified Chinese (`zh-CN`)
- Files under `assets/translations/` (JSON). Add new keys in both languages.
- The app is wired with `easy_localization` in `main.dart`.

Build and run:
- Common
  - Fetch deps: `flutter pub get`
  - Analyze: `flutter analyze`
  - Test (if tests present): `flutter test`

- Android
  - Run debug: `flutter run -d android`
  - Build APK: `flutter build apk`
  - Build AppBundle: `flutter build appbundle`
  - Make sure the Casdoor URL scheme intent filter and BLE permissions (Android 12+) are configured

- iOS
  - Run: `flutter run -d ios` (open Xcode for signing if needed)
  - Build: `flutter build ios`
  - Ensure URL scheme and any required Bluetooth privacy strings are in `Info.plist`

- macOS
  - Run: `flutter run -d macos`
  - Build: `flutter build macos`

- Windows
  - Run: `flutter run -d windows`
  - Build: `flutter build windows`

- Linux
  - Run: `flutter run -d linux`
  - Build: `flutter build linux`

- Web (optional/beta)
  - Ensure `web/callback.html` exists if using Casdoor
  - Run: `flutter run -d chrome`
  - Build: `flutter build web`

## Bring your own gateway/device

To integrate a custom DALI gateway or transport, follow this checklist:

1) Implement a connection/transport
   - Add a file under `lib/connection/` (use `ble.dart`, `serial_usb.dart`, `serial_ip.dart`, or `ble_web.dart` as references)
   - Provide: connect/disconnect, send (write), receive (stream) primitives
   - After connecting, call `ConnectionManager.instance.ensureGatewayType()` once
   - Feed idle-monitor bytes to `ConnectionManager` so Type0 bus status can be inferred (`markBusAbnormal()` when `0xFF 0xFD` is detected)

2) Wire into the app
   - Trigger your transport from settings or auto-discovery (see `widgets/settings/gateway_type_card.dart` and the existing connection entries)
   - Update any selection UI and persist preferences if needed

3) Platform setup
   - Android: add permissions/intents (BLE: BLUETOOTH_SCAN/CONNECT on Android 12+, location on <=11; custom schemes for Casdoor)
   - iOS/macOS: add URL schemes, Bluetooth privacy strings if applicable
   - Web: ensure required features (WebBLE) and HTTPS origin, plus `web/callback.html` for Casdoor

4) Validate
   - Verify gateway type detection and that bus operations are blocked when status is abnormal
   - Smoke test address allocation, queries, and sequences against your hardware

Minimal runtime contract:
- Inputs: raw frames to gateway; idle-monitor stream for Type0
- Outputs: device responses (bytes); gateway type (0/1/2/3) determined by probe
- Error modes: timeouts, bus abnormal (block operations), permission denied
- Success: stable connect/disconnect, accurate gateway detection, correct read/write

## Build instructions

This project no longer depends on a bundled server submodule. To build locally:

```bash
flutter pub get
flutter analyze
# optional
flutter test

# run on a connected device
flutter run -d <device_id>

# build for your target
flutter build <apk|appbundle|ios|macos|linux|windows|web>
```

If you maintain a separate backend, configure its URL/endpoints in your own code or environment; it is not required to compile and run the app.
