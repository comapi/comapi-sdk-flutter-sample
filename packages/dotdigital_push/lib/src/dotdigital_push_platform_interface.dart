import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'models.dart';
import 'dotdigital_push_method_channel.dart';

/// Common platform interface for Dotdigital Mobile Push integrations.
abstract class DotdigitalPushPlatform extends PlatformInterface {
  DotdigitalPushPlatform() : super(token: _token);

  static final Object _token = Object();

  static DotdigitalPushPlatform _instance = MethodChannelDotdigitalPush();

  /// The default instance of [DotdigitalPushPlatform] to use.
  static DotdigitalPushPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DotdigitalPushPlatform] when
  /// they register themselves.
  static set instance(DotdigitalPushPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Initializes the native Dotdigital/Comapi SDK with the provided [config].
  ///
  /// Returns `true` if initialization succeeded, or `false` otherwise.
  Future<bool> initialize(DotdigitalConfig config) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Prompts the user to grant push notification permissions from the OS.
  ///
  /// On Android 13+, requests `android.permission.POST_NOTIFICATIONS`.
  /// On iOS, requests authorization via `UNUserNotificationCenter`.
  /// Returns `true` if permission was granted.
  Future<bool> requestNotificationPermissions() {
    throw UnimplementedError('requestNotificationPermissions() has not been implemented.');
  }

  Future<PushPermissionStatus> getNotificationPermissionStatus() {
    throw UnimplementedError('getNotificationPermissionStatus() has not been implemented.');
  }

  Future<bool> openNotificationSettings() {
    throw UnimplementedError('openNotificationSettings() has not been implemented.');
  }

  Future<bool> registerPushToken() {
    throw UnimplementedError('registerPushToken() has not been implemented.');
  }

  /// Starts an authenticated Dotdigital push session.
  ///
  /// Triggers the native authentication challenge handler and registers the
  /// device's push token (APNs / FCM) with Dotdigital.
  Future<bool> startSession() {
    throw UnimplementedError('startSession() has not been implemented.');
  }

  /// Ends the active Dotdigital push session.
  ///
  /// Removes the token from Dotdigital Marketing without revoking the device token.
  Future<bool> endSession() {
    throw UnimplementedError('endSession() has not been implemented.');
  }

  /// Patches the user's push profile with their [email] address.
  ///
  /// Required for Dotdigital Audience Discovery to associate the device's
  /// push token with a marketing contact.
  Future<bool> updateUserEmail(String email) {
    throw UnimplementedError('updateUserEmail() has not been implemented.');
  }

  /// Retrieves the device's APNs / FCM push token from the native layer.
  Future<String?> getPushToken() {
    throw UnimplementedError('getPushToken() has not been implemented.');
  }

  /// Retrieves the current session status, active profile ID, and token state.
  Future<DotdigitalSessionState> getSessionState() {
    throw UnimplementedError('getSessionState() has not been implemented.');
  }

  /// Returns the notification tap event that opened the app from a cold-start, if any.
  Future<PushTapEvent?> getInitialNotification() {
    throw UnimplementedError('getInitialNotification() has not been implemented.');
  }

  /// Opens a deep link or external URL, and triggers Dotdigital click tracking
  /// if [rawPayload] contains a `dd_deepLink` tracking URL.
  Future<bool> openDeepLink({
    required String url,
    Map<String, dynamic>? rawPayload,
    bool launchExternal = true,
  }) {
    throw UnimplementedError('openDeepLink() has not been implemented.');
  }

  /// Broadcast stream of push notifications arriving while the app is in foreground.
  Stream<PushNotification> get onPushReceived {
    throw UnimplementedError('onPushReceived has not been implemented.');
  }

  /// Broadcast stream of notification tap events (from system tray or toast).
  Stream<PushTapEvent> get onNotificationTapped {
    throw UnimplementedError('onNotificationTapped has not been implemented.');
  }

  /// Broadcast stream of silent data pushes (`dd_data` with `isSilent: true`).
  Stream<SilentPushEvent> get onSilentPushReceived {
    throw UnimplementedError('onSilentPushReceived has not been implemented.');
  }

  Stream<String> get onPushTokenReceived => const Stream.empty();

  /// Sets a custom callback to handle authentication challenges (e.g. for backend signing).
  void setChallengeHandler(Future<String?> Function(String nonce) handler) {
    throw UnimplementedError('setChallengeHandler() has not been implemented.');
  }
}
