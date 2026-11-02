import 'src/dotdigital_push_platform_interface.dart';
import 'src/models.dart';

export 'src/models.dart';

/// Entrypoint for Dotdigital Mobile Push channel integration.
class DotdigitalPush {
  static DotdigitalPushPlatform get _platform => DotdigitalPushPlatform.instance;

  /// Configure the Dotdigital / Comapi SDK.
  static Future<bool> initialize(DotdigitalConfig config) {
    return _platform.initialize(config);
  }

  /// Request runtime push notification permissions from the OS
  /// (e.g. POST_NOTIFICATIONS on Android 13+, UNUserNotificationCenter on iOS).
  static Future<bool> requestNotificationPermissions() {
    return _platform.requestNotificationPermissions();
  }

  static Future<PushPermissionStatus> getNotificationPermissionStatus() {
    return _platform.getNotificationPermissionStatus();
  }

  static Future<bool> openNotificationSettings() {
    return _platform.openNotificationSettings();
  }

  static Future<bool> registerPushToken() {
    return _platform.registerPushToken();
  }

  /// Start an authenticated Dotdigital SDK push session.
  /// Acquires token from APNs/FCM and satisfies the authentication challenge.
  static Future<bool> startSession() {
    return _platform.startSession();
  }

  /// End the current session.
  /// Removes the token from Dotdigital Marketing without revoking the device token.
  static Future<bool> endSession() {
    return _platform.endSession();
  }

  /// Patches the Dotdigital push profile with the user's email address.
  ///
  /// Required for Dotdigital Marketing contact discovery:
  /// Dotdigital syncs contacts and populates PUSHOPTIN_xxx only when both
  /// a registered device push token AND an email address are set.
  static Future<bool> updateUserEmail(String email) {
    return _platform.updateUserEmail(email);
  }

  /// Returns the device's APNs / FCM token, if available.
  /// A token alone does not confirm an active Dotdigital session.
  static Future<String?> getPushToken() {
    return _platform.getPushToken();
  }

  /// Returns the current active session state (profile ID, active status, etc.).
  static Future<DotdigitalSessionState> getSessionState() {
    return _platform.getSessionState();
  }

  /// Retrieves the notification tap event if the app was launched cold by tapping a push.
  static Future<PushTapEvent?> getInitialNotification() {
    return _platform.getInitialNotification();
  }

  /// Opens an external web URL or deep link and records Dotdigital click tracking
  /// if [rawPayload] contains a `dd_deepLink` tracking URL.
  static Future<bool> openDeepLink({
    required String url,
    Map<String, dynamic>? rawPayload,
    bool launchExternal = true,
  }) {
    return _platform.openDeepLink(
      url: url,
      rawPayload: rawPayload,
      launchExternal: launchExternal,
    );
  }

  /// Stream of push notifications received while app is in foreground.
  static Stream<PushNotification> get onPushReceived => _platform.onPushReceived;

  /// Stream of notification tap events (from background or foreground).
  /// Delivers deep link URLs, custom data, and click-tracking verification status.
  static Stream<PushTapEvent> get onNotificationTapped => _platform.onNotificationTapped;

  /// Stream of silent background data pushes (data-only / content-available: 1).
  static Stream<SilentPushEvent> get onSilentPushReceived => _platform.onSilentPushReceived;

  static Stream<String> get onPushTokenReceived => _platform.onPushTokenReceived;

  /// Optional custom authentication challenge handler (e.g. to fetch JWT from backend).
  static void setChallengeHandler(Future<String?> Function(String nonce) handler) {
    _platform.setChallengeHandler(handler);
  }
}
