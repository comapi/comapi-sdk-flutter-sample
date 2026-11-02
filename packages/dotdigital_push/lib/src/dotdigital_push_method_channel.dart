import 'dart:async';
import 'package:flutter/services.dart';
import 'dotdigital_push_platform_interface.dart';
import 'models.dart';

/// An implementation of [DotdigitalPushPlatform] that uses method channels.
class MethodChannelDotdigitalPush extends DotdigitalPushPlatform {
  final MethodChannel _channel = const MethodChannel('com.dotdigital.push/methods');

  final StreamController<PushNotification> _pushReceivedController =
      StreamController<PushNotification>.broadcast();

  final StreamController<PushTapEvent> _notificationTappedController =
      StreamController<PushTapEvent>.broadcast();

  final StreamController<SilentPushEvent> _silentPushReceivedController =
      StreamController<SilentPushEvent>.broadcast();
    final StreamController<String> _pushTokenReceivedController =
      StreamController<String>.broadcast();

  Future<String?> Function(String nonce)? _challengeHandler;
  DotdigitalConfig? _lastConfig;

  /// Creates a method channel instance and registers the native method call handler.
  MethodChannelDotdigitalPush() {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  /// Dispatches incoming method calls from native Android (Kotlin) and iOS (Swift).
  ///
  /// Handles:
  /// - `onAuthenticationChallenge`: Supplies a signed JWT in response to a nonce.
  /// - `onPushReceived`: Emits foreground push notification to the Dart stream.
  /// - `onNotificationTapped`: Emits user tap events with deep links and click tracking.
  /// - `onSilentPushReceived`: Emits background data-only payloads (`dd_data`).
  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPushTokenReceived':
        final token = call.arguments;
        if (token is String && token.isNotEmpty) {
          _pushTokenReceivedController.add(token);
        }
        return null;

      case 'onAuthenticationChallenge':
        final args = call.arguments != null ? Map<String, dynamic>.from(call.arguments as Map) : {};
        final nonce = args['nonce'] as String? ?? '';
        if (_challengeHandler != null) {
          return await _challengeHandler!(nonce);
        }
        if (_lastConfig != null && _lastConfig!.sharedSecret != null) {
          return _lastConfig!.generateJwt(nonce: nonce);
        }
        return null;

      case 'onPushReceived':
        if (call.arguments != null) {
          final map = Map<String, dynamic>.from(call.arguments as Map);
          _pushReceivedController.add(PushNotification.fromMap(map));
        }
        return null;

      case 'onNotificationTapped':
        if (call.arguments != null) {
          final map = Map<String, dynamic>.from(call.arguments as Map);
          _notificationTappedController.add(PushTapEvent.fromMap(map));
        }
        return null;

      case 'onSilentPushReceived':
        if (call.arguments != null) {
          final map = Map<String, dynamic>.from(call.arguments as Map);
          _silentPushReceivedController.add(SilentPushEvent.fromMap(map));
        }
        return null;

      default:
        return null;
    }
  }

  @override
  void setChallengeHandler(Future<String?> Function(String nonce) handler) {
    _challengeHandler = handler;
  }

  @override
  Future<bool> initialize(DotdigitalConfig config) async {
    _lastConfig = config;
    final result = await _channel.invokeMethod<bool>('initialize', config.toMap());
    return result ?? false;
  }

  @override
  Future<bool> requestNotificationPermissions() async {
    final result = await _channel.invokeMethod<bool>('requestNotificationPermissions');
    return result ?? false;
  }

  @override
  Future<PushPermissionStatus> getNotificationPermissionStatus() async {
    final value = await _channel.invokeMethod<String>('getNotificationPermissionStatus');
    return PushPermissionStatus.values.where((status) => status.name == value).firstOrNull ??
        PushPermissionStatus.unknown;
  }

  @override
  Future<bool> openNotificationSettings() async {
    return await _channel.invokeMethod<bool>('openNotificationSettings') ?? false;
  }

  @override
  Future<bool> registerPushToken() async {
    return await _channel.invokeMethod<bool>('registerPushToken') ?? false;
  }

  @override
  Future<bool> startSession() async {
    final result = await _channel.invokeMethod<bool>('startSession');
    return result ?? false;
  }

  @override
  Future<bool> endSession() async {
    final result = await _channel.invokeMethod<bool>('endSession');
    return result ?? false;
  }

  @override
  Future<bool> updateUserEmail(String email) async {
    final result = await _channel.invokeMethod<bool>('updateUserEmail', {'email': email});
    return result ?? false;
  }

  @override
  Future<String?> getPushToken() async {
    return await _channel.invokeMethod<String>('getPushToken');
  }

  @override
  Future<DotdigitalSessionState> getSessionState() async {
    final result = await _channel.invokeMethod<Map>('getSessionState');
    if (result != null) {
      return DotdigitalSessionState.fromMap(Map<String, dynamic>.from(result));
    }
    return const DotdigitalSessionState(isSessionActive: false);
  }

  @override
  Future<PushTapEvent?> getInitialNotification() async {
    final result = await _channel.invokeMethod<Map>('getInitialNotification');
    if (result != null) {
      return PushTapEvent.fromMap(Map<String, dynamic>.from(result));
    }
    return null;
  }

  @override
  Future<bool> openDeepLink({
    required String url,
    Map<String, dynamic>? rawPayload,
    bool launchExternal = true,
  }) async {
    final result = await _channel.invokeMethod<bool>('openDeepLink', {
      'url': url,
      'rawPayload': rawPayload,
      'launchExternal': launchExternal,
    });
    return result ?? false;
  }

  @override
  Stream<PushNotification> get onPushReceived => _pushReceivedController.stream;

  @override
  Stream<PushTapEvent> get onNotificationTapped => _notificationTappedController.stream;

  @override
  Stream<SilentPushEvent> get onSilentPushReceived => _silentPushReceivedController.stream;

  @override
  Stream<String> get onPushTokenReceived => _pushTokenReceivedController.stream;
}
