# Dotdigital Mobile Push Example App (Flutter)

A Flutter application demonstrating integration with the **Dotdigital Mobile Push Channel** across **Android** and **iOS**, based on the official [Dotdigital Push Notifications Documentation](https://marketing.developer.dotdigital.com/docs/setting-up-push-notifications).

The app showcases:
- **Contact Discovery & User Registration**: Initializing the native Comapi Foundation SDK, completing cryptographic authentication challenges (JWT HS256), registering device push tokens, and patching user profiles with email addresses to populate `PUSHOPTIN_xxx` in Dotdigital Marketing.
- **In-App Toast Banner**: Displaying animated top toast alerts when push notifications arrive in the foreground, with one-tap deep link routing and dismiss actions.
- **Notification Inbox & History**: Reviewing up to 50 recorded events, including foreground alerts, notification taps, silent data events, and simulations, with raw payload inspection.
- **Deep Linking (`ddexample:`)**: Intercepting and routing custom schemes (`ddexample://product/:id` and `ddexample://promo`).
- **Dotdigital Click Tracking**: Passing notification taps to the native SDK for eligible deep-link click tracking.
- **Silent Background Data Pushes**: Handling `dd_data` background updates (`isSilent: true` / data-only) without user interruption when they are delivered to the app.
- **Session Lifecycle Management**: Ending the SDK session on sign-out or user switching. This removes the push token from Dotdigital Marketing. The device token itself stays valid, so that the next user can register it.
- **Modular Plugin Architecture**: Bridges native SDKs via a local Flutter plugin ([packages/dotdigital_push](packages/dotdigital_push)).

---

## Architecture Overview

```
dotdigital_flutter_example/
├── lib/
│   ├── main.dart                          # App entry point, deep link router & toast overlay
│   ├── models/
│   │   └── notification_history_item.dart # Data model for inbox & history items
│   ├── screens/
│   │   ├── dashboard_screen.dart          # Status dashboard, action triggers & live activity log
│   │   ├── config_screen.dart             # In-app credentials & JWT config UI
│   │   ├── notification_inbox_screen.dart # Notification inbox & payload viewer
│   │   ├── product_detail_screen.dart     # Deep link target for ddexample://product/:id
│   │   └── promo_screen.dart              # Deep link target for ddexample://promo
│   ├── services/
│   │   └── notification_service.dart      # Central state, push streams & persistence
│   └── widgets/
│       └── in_app_toast.dart              # Foreground animated toast banner
└── packages/
   └── dotdigital_push/                   # Local Flutter plugin
      ├── android/                       # Kotlin bridge to com.comapi:foundation:1.8.1 & FCM
      ├── ios/                           # Swift bridge to CMPComapiFoundation & APNs
      └── lib/                           # Dart API interface, streams & JWT generator
```

---

## Configuration & Prerequisites

Before compiling and running on physical devices or emulators, configure the platform credentials below.

This example starts with no account credentials. Use a dedicated test profile and test contact. The app stores configuration, including a locally entered shared secret, in device preferences. Local JWT signing is for testing only; production apps must obtain signed tokens from an authenticated backend. The optional `backendAuthUrl` field is not connected to a backend in this example.

### Summary: Which Files Need Updating?

| Credential / Item | File to Update | Description |
| :--- | :--- | :--- |
| **Push profile credentials** | **Credentials & Config** in the app | Enter the API Space ID, shared secret, issuer, audience, user ID, and test contact email. |
| **Firebase Services File** | `android/app/google-services.json` | Download your project's file from Firebase; it is not included in this repository. |
| **Android Package Name (Optional)** | [android/app/build.gradle.kts](android/app/build.gradle.kts), [MainActivity.kt](android/app/src/main/kotlin/com/example/dotdigital_flutter_example/MainActivity.kt) | Update `applicationId`, `namespace`, and the activity package if using your own package ID (default: `com.example.dotdigital_flutter_example`). |
| **iOS Bundle Identifier (Optional)** | `ios/Runner.xcodeproj/project.pbxproj` / Xcode | Update `PRODUCT_BUNDLE_IDENTIFIER` if using your own bundle ID (default: `com.example.dotdigitalFlutterExample`). |
| **iOS Team & Signing** | Xcode (`ios/Runner.xcworkspace`) | Set your Apple Developer Team in **Signing & Capabilities**. |

---

### 1. Dotdigital Marketing Account Setup
1. Log in to **Dotdigital Marketing**.
2. Navigate to **Connect** > **Digital marketing channels** > **Push Notification**, then select **New profile**.
3. Enter your app name and note the values in the **Authentication** section:
   - **Shared Secret**: Secret key used to sign authentication JWTs with HMAC-SHA256.
   - **Issuer (`iss`)**: Defaults to `https://api.comapi.com/defaultauth`.
   - **Audience (`aud`)**: Defaults to `https://api.comapi.com`.
   - **ID claim**: This example uses `sub` for the user ID.
4. Configure the Android and/or iOS credentials below, set the profile **Status** to **Enabled**, and save it. Note the **API Space ID** shown on the profile after saving. See [Create a push notification profile](https://marketing.developer.dotdigital.com/docs/creating-a-push-notification-profile-new) for details.

#### Where to enter these credentials
Launch the app, tap the **gear icon** to open **Credentials & Config**, enter your test profile values, and save. Previously saved configuration takes precedence over the empty defaults; update it in the app when switching profiles. Never commit your shared secret or production credentials.

---

### 2. Android Configuration (FCM)
The Android integration uses **Firebase Cloud Messaging (FCM)** and `com.comapi:foundation:1.8.1`.

1. Go to the [Firebase Console](https://console.firebase.google.com/) and create or open your project.
2. Add an Android app with package name:
   ```
   com.example.dotdigital_flutter_example
   ```
   *(If you change this package name, update `applicationId` and `namespace` in [android/app/build.gradle.kts](android/app/build.gradle.kts), and update the package declaration in [MainActivity.kt](android/app/src/main/kotlin/com/example/dotdigital_flutter_example/MainActivity.kt) to match the namespace. The manifest's `.MainActivity` name resolves against that namespace.)*
3. Download the generated `google-services.json` file.
4. Place the downloaded file at `android/app/google-services.json` before building or enabling push. This file is ignored by Git; do not commit another project's configuration.
5. In Dotdigital Marketing:
   - Go to your Push Notification Profile's **App system: Android** section and enter the matching package name.
   - Upload your Firebase service account private key JSON file (generated in Firebase Console under **Project Settings** > **Service accounts**).
   - Keep the private key outside this repository; it is not the same file as `google-services.json`.
6. Custom scheme `ddexample:` is pre-configured in [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml).

---

### 3. iOS Configuration (APNs)
The iOS integration uses **Apple Push Notification service (APNs)** and `CMPComapiFoundation`.

Build and run the iOS app on macOS with Xcode and Flutter's Swift Package Manager integration enabled. The local plugin declares `CMPComapiFoundation` from the official Swift package; Flutter resolves it when building the app, so do not add the SDK separately in Xcode.

1. In the [Apple Developer Member Center](https://developer.apple.com/account/):
   - Under **Certificates, Identifiers & Profiles**, select **Keys** and create an **APNs Key** (`.p8` file). Note the **Key ID** and your **Team ID**.
   - Under **Identifiers**, enable the **Push Notifications** capability on your App ID.
2. In Dotdigital Marketing:
   - Go to your Push Notification Profile's **App system: iOS** section.
   - Upload the `.p8` key file and enter your **Key ID** and **Team ID**.
3. In Xcode (`ios/Runner.xcworkspace`):
   - Open the Runner target's **Signing & Capabilities**, set your development team, and use the bundle identifier registered with Apple (default: `com.example.dotdigitalFlutterExample`).
   - Confirm **Push Notifications** is enabled for Runner and the provisioning profile includes the `aps-environment` entitlement. The project already declares the capability.
   - For silent pushes, enable **Background Modes** with **Remote notifications** checked. The setting is already present in [ios/Runner/Info.plist](ios/Runner/Info.plist).
   - Custom scheme `ddexample:` is pre-configured in [ios/Runner/Info.plist](ios/Runner/Info.plist).
4. Check that the APNs environment matches your build and provisioning profile: development for debug builds, production for TestFlight, ad hoc, and App Store builds. The plugin passes this environment to the Swift package using the Swift `DEBUG` flag by default; an explicit `apnsEnvironment` can override it. See the [iOS SDK guidance](https://marketing.developer.dotdigital.com/docs/ios-sdk-new#set-up-the-apns-environment).
5. Rebuild and reinstall the app after changing signing or capabilities. Simulator APNs requires iOS 16 or later on macOS 13 or later with Apple silicon or a T2 chip; a physical device is recommended for end-to-end testing.

---

## Compiling & Running the App

### Step 1: Install Dependencies
```bash
flutter pub get
cd packages/dotdigital_push
flutter pub get
cd ../..
```
Flutter recreates the ignored Android Gradle wrapper when needed.

### Step 2: Run Tests & Static Analysis
```bash
flutter analyze
flutter test
flutter test packages/dotdigital_push/test
```

### Step 3: Launch the Application
- **Android Device / Emulator**:
  ```bash
  flutter run -d <android-device-id>
  ```
- **iOS Device** *(a physical device is recommended for APNs testing)*:
  ```bash
  flutter run -d <ios-device-id>
  ```

Android release builds currently use the debug signing key and are not suitable for distribution. Configure a separate release signing key outside the repository before publishing an Android app.

---

## Using the Example App

### Lifecycle
1. Open **Credentials & Config** and enter the API Space ID, user ID, authentication settings and contact email.
2. Select **Enable push** and grant notification permission when prompted. The app initializes the SDK, starts a session if needed, and syncs the email once. Existing installations must also confirm with **Enable push** once.
3. On later launches, an opted-in user is initialized automatically. An active session for the same user is reused; otherwise a new session is started. Permission is checked without another prompt, and an unchanged email is not synced again.
4. If permission is disabled, use **Notification settings** and return to the app. Errors and pending opt-outs have a **Retry** action.
5. Select **End session / Opt out** to stop automatic restoration. After enabling push, changing the API space or user ends the previous session before saving and requires the new user to enable push. Changing the API space after SDK initialization also requires an app restart. A failed teardown remains pending and must be retried.
6. In Dotdigital Marketing, check the contact's **Devices** tab for the registered device and `PUSHOPTIN_xxx`. The email sync status records the last successful update from this app; it does not verify subsequent server-side changes.

If the token remains pending, check notification permission, platform signing and credentials, and the native debug console. APNs and FCM registration are asynchronous; pull down to refresh the dashboard if needed. A session can be active without a registered push token. Activity logs and notification history can contain contact data or notification payloads, so review them before sharing.

Ending a session does not revoke the device's FCM or APNs token, by design. See [Unregistering app users](https://marketing.developer.dotdigital.com/docs/registering-your-app-users-for-push#unregistering-app-users).

### Testing Push Scenarios
- **Simulate In-App Push**: Use the dashboard test chips to trigger a foreground toast, product deep link (`ddexample://product/42`), promo deep link (`ddexample://promo`), or silent data push.
- **Send from Dotdigital**: Send a push campaign via Dotdigital Program Builder or Omnichannel API. Foreground alerts show an in-app toast and may also show a system notification; background alerts may appear in the system tray. A tap can open a configured deep link. Click tracking requires an eligible deep link with a tracking URL; Program Builder's **Open app** and **Pass data** actions do not report clicks. API sends use a tracking link supplied by the caller.
- **Review Inbox**: Tap the inbox icon to inspect recorded events and their payloads. The inbox retains the latest 50 entries; it is not a complete record of every notification. Silent pushes are subject to operating-system delivery limits, and background events may not be recorded when the Flutter app is not running.

---