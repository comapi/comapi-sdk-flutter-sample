import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dotdigital_push/dotdigital_push.dart';
import '../models/notification_history_item.dart';

// ============================================================================
// NOTIFICATION SERVICE - HIGH LEVEL LIFECYCLE & NARRATIVE
// ============================================================================
// This singleton coordinates all push notification operations for the Flutter app:
//
// 1. CONFIGURATION & PERSISTENCE:
//    Loads and stores Dotdigital configuration (API Space ID, User ID, Contact Email, etc.)
//    in SharedPreferences so values survive app restarts.
//
//    ⚠️ SECURITY WARNING:
//    The default credentials provided here and in the UI are for demonstration,
//    local testing, and documentation validation ONLY. Storing a Shared Secret
//    directly inside a mobile application allows reverse-engineers to extract it.
//    In production, tokens must be created and signed on an authenticated backend server.
//
// 2. INITIALIZATION (`initializeSdk`):
//    Configures the native Comapi Foundation SDK with the `apiSpaceId` and sets up
//    the authentication and message listeners on Android and iOS.
//
// 3. PERMISSION & TOKEN REGISTRATION (`requestPermissions`):
//    Prompts the user for runtime notification permissions (POST_NOTIFICATIONS on
//    Android 13+, UNUserNotificationCenter on iOS). Once approved, the operating system
//    issues a push token (FCM / APNs) that the SDK collects automatically.
//
// 4. SESSION LIFECYCLE (`startSession` / `endSession`):
//    Starting a session triggers the authentication challenge flow where the JWT is supplied.
//    Ending a session unregisters the push token from the contact profile in Dotdigital.
//
// 5. CONTACT DISCOVERY (`updateUserEmail`):
//    Dotdigital requires an email address on the push profile to link the mobile device
//    to a Marketing contact. This service retrieves the latest profile eTag and patches
//    the profile with the email address, activating the `PUSHOPTIN_xxx` channel field.
//
// 6. EVENT DISPATCH & INBOX REVIEW:
//    - Incoming foreground messages trigger an in-app animated toast banner.
//    - Incoming background/tapped messages trigger click analytics tracking and route `ddexample:` deep links.
//    - Silent background data pushes (`dd_data`) are logged silently without user-facing alerts.
//    - All notifications are persisted to an inbox for review.
// ============================================================================

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  @visibleForTesting
  NotificationService.forTesting();

  /// Default configuration placeholders.
  ///
  /// ⚠️ NOTE: Replace with your actual Dotdigital Marketing Push Notification Profile
  /// values via the in-app Configuration Screen or by editing these defaults.
  DotdigitalConfig _config = const DotdigitalConfig(
    apiSpaceId: '',
    userId: '',
  );

  DotdigitalConfig get config => _config;

  bool _isInitialized = false;
  String? _initializedApiSpaceId;
  bool get restartRequired => _initializedApiSpaceId != null &&
      _initializedApiSpaceId != _config.apiSpaceId;
  bool get isInitialized => _isInitialized && !restartRequired;

  DotdigitalSessionState _sessionState = const DotdigitalSessionState(isSessionActive: false);
  DotdigitalSessionState get sessionState => _sessionState;

  String _pushIntent = 'unconfirmed';
  String? _syncedEmail;
  PushPermissionStatus _permissionStatus = PushPermissionStatus.unknown;
  bool _lifecycleBusy = false;
  String? _lifecycleError;

  bool get isPushEnabled => _pushIntent == 'enabled';
  bool get isOptOutPending => _pushIntent == 'pending';
  bool get needsConfirmation => _pushIntent == 'unconfirmed';
  bool get hasMatchingSession => _sessionState.isSessionActive &&
      _sessionState.profileId == _config.userId;
  PushPermissionStatus get permissionStatus => _permissionStatus;
  bool get lifecycleBusy => _lifecycleBusy;
  String? get lifecycleError => _lifecycleError;
  bool get isEmailSynced => _config.contactEmail != null &&
      _syncedEmail == _config.contactEmail!.trim().toLowerCase();

  final List<NotificationHistoryItem> _history = [];
  List<NotificationHistoryItem> get history => List.unmodifiable(_history);

  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

  final StreamController<NotificationHistoryItem> _toastController =
      StreamController<NotificationHistoryItem>.broadcast();
  Stream<NotificationHistoryItem> get onShowToast => _toastController.stream;

  final StreamController<DeepLinkNavigationEvent> _deepLinkNavigationController =
      StreamController<DeepLinkNavigationEvent>.broadcast();
  Stream<DeepLinkNavigationEvent> get onNavigateDeepLink => _deepLinkNavigationController.stream;

  StreamSubscription? _pushSub;
  StreamSubscription? _tapSub;
  StreamSubscription? _silentSub;
  StreamSubscription? _pushTokenSub;

  /// Initializes the service by loading persisted configs, history, and subscribing to push streams.
  Future<void> init() async {
    await _loadConfig();
    await _loadHistory();
    await _loadLifecycle();
    _setupListeners();
  }

  /// Appends an activity log message and notifies listeners.
  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final entry = '[$timestamp] $message';
    _logs.insert(0, entry);
    if (_logs.length > 100) _logs.removeLast();
    notifyListeners();
  }

  /// Extracts a URL or deep link from direct `url`, `customData` (`dd_data`), or `rawPayload` (`dd_deepLink`).
  static String? extractUrlFromPayload({
    String? directUrl,
    Map<String, dynamic>? customData,
    Map<String, dynamic>? rawPayload,
  }) {
    if (directUrl != null && directUrl.trim().isNotEmpty) {
      return directUrl.trim();
    }

    const urlKeys = ['url', 'deepLink', 'deeplink', 'link', 'uri'];

    String? findInMap(Map<dynamic, dynamic>? map) {
      if (map == null) return null;
      for (final key in urlKeys) {
        final val = map[key];
        if (val is String && val.trim().isNotEmpty) {
          return val.trim();
        }
      }
      return null;
    }

    final fromCustom = findInMap(customData);
    if (fromCustom != null) return fromCustom;

    if (rawPayload != null) {
      final fromRawTop = findInMap(rawPayload);
      if (fromRawTop != null) return fromRawTop;

      final ddDeepLink = rawPayload['dd_deepLink'];
      if (ddDeepLink is Map) {
        final found = findInMap(ddDeepLink);
        if (found != null) return found;
      } else if (ddDeepLink is String && ddDeepLink.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(ddDeepLink);
          if (decoded is Map) {
            final found = findInMap(decoded);
            if (found != null) return found;
          }
        } catch (_) {}
      }

      final ddData = rawPayload['dd_data'];
      if (ddData is Map) {
        final found = findInMap(ddData);
        if (found != null) return found;
      } else if (ddData is String && ddData.trim().isNotEmpty) {
        final trimmed = ddData.trim();
        if (trimmed.startsWith('http://') ||
            trimmed.startsWith('https://') ||
            trimmed.startsWith('ddexample://')) {
          return trimmed;
        }
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            final found = findInMap(decoded);
            if (found != null) return found;
          }
        } catch (_) {}
      }
    }

    return null;
  }

  /// Subscribes to native push event streams (foreground, taps, and silent pushes).
  void _setupListeners() {
    _pushSub?.cancel();
    _tapSub?.cancel();
    _silentSub?.cancel();
    _pushTokenSub?.cancel();

    _pushTokenSub = DotdigitalPush.onPushTokenReceived.listen((token) {
      _sessionState = DotdigitalSessionState(
        isSessionActive: _sessionState.isSessionActive,
        profileId: _sessionState.profileId,
        deviceId: _sessionState.deviceId,
        pushToken: token,
        currentEmail: _sessionState.currentEmail,
      );
      _log('Device push token received.');
    });

    // 1. Foreground Push Notifications
    _pushSub = DotdigitalPush.onPushReceived.listen((push) {
      final resolvedUrl = extractUrlFromPayload(
        directUrl: push.deepLinkUrl,
        customData: push.customData,
        rawPayload: push.rawPayload,
      );
      _log('Foreground push received: "${push.title ?? "No title"}"${resolvedUrl != null ? " (url: $resolvedUrl)" : ""}');
      final item = NotificationHistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: push.title ?? 'New Message',
        body: push.body ?? '',
        deepLinkUrl: resolvedUrl,
        customData: push.customData ?? {},
        rawPayload: push.rawPayload,
        type: resolvedUrl != null ? NotificationType.deepLink : NotificationType.standard,
        receivedAt: push.timestamp,
      );

      _addHistoryItem(item);
      _toastController.add(item);
    });

    // 2. Notification Tap Events (handles deep links and Dotdigital click tracking)
    _tapSub = DotdigitalPush.onNotificationTapped.listen((tap) {
      final resolvedUrl = extractUrlFromPayload(
        directUrl: tap.url,
        customData: tap.customData,
        rawPayload: tap.rawPayload,
      );

      _log(
        'Notification tapped: url="$resolvedUrl", clickRecorded=${tap.isClickRecorded}, deepLinkLaunched=${tap.isDeepLinkCalled}',
      );

      final item = NotificationHistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Notification Tap',
        body: resolvedUrl != null ? 'Opened deep link: $resolvedUrl' : 'Tapped notification payload',
        deepLinkUrl: resolvedUrl,
        customData: tap.customData ?? {},
        rawPayload: tap.rawPayload,
        type: resolvedUrl != null ? NotificationType.deepLink : NotificationType.standard,
        receivedAt: tap.timestamp,
        isClickRecorded: tap.isClickRecorded,
        isDeepLinkCalled: tap.isDeepLinkCalled,
      );

      _addHistoryItem(item);

      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        _deepLinkNavigationController.add(
          DeepLinkNavigationEvent(
            url: resolvedUrl,
            extraData: tap.customData,
            rawPayload: tap.rawPayload,
          ),
        );
      }
    });

    // 3. Silent Data Pushes
    _silentSub = DotdigitalPush.onSilentPushReceived.listen((silent) {
      _log('Silent push received: ${silent.customData}');
      final item = NotificationHistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Silent Background Push',
        body: 'Custom data payload: ${jsonEncode(silent.customData ?? {})}',
        customData: silent.customData ?? {},
        rawPayload: silent.rawPayload,
        type: NotificationType.silentData,
        receivedAt: silent.timestamp,
      );

      _addHistoryItem(item);
    });
  }

  Future<bool> _runLifecycle(Future<void> Function() action) async {
    if (_lifecycleBusy) return false;
    _lifecycleBusy = true;
    _lifecycleError = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (error) {
      _lifecycleError = _describeLifecycleError(error);
      _log('Lifecycle error: $_lifecycleError');
      return false;
    } finally {
      _lifecycleBusy = false;
      notifyListeners();
    }
  }

  String _describeLifecycleError(Object error) {
    if (error is! PlatformException || error.code != 'START_SESSION_FAILED') {
      return error.toString();
    }
    final details = error.details is Map ? error.details as Map : const {};
    final isUnexpectedIosResponse =
        (details['domain'] == 'com.comapi.foundation.request.template' && details['code'] == 5554) ||
        (error.message?.contains('com.comapi.foundation.request.template error 5554') ?? false);
    if (!isUnexpectedIosResponse) return error.toString();

    if (details['underlyingDomain'] == 'NSURLErrorDomain' && details['underlyingCode'] is int) {
      if (details['underlyingCode'] == -1000 || details['underlyingCode'] == -1002) {
        return 'Session request failed because the SDK URL is invalid or unsupported '
            '(iOS network error code ${details['underlyingCode']}). Check the SDK API endpoint configuration.';
      }
      return 'Session request failed due to an iOS network error (code ${details['underlyingCode']}). '
          'Check the device connection and network configuration, then try again.';
    }
    const statusNote = 'The iOS SDK did not provide the HTTP status.';
    if (details['challengeReceived'] == true) {
      return 'Session request failed after the authentication challenge. '
          'Check the push profile Shared Secret, Issuer, Audience, and ID claim. $statusNote';
    }
    if (details['challengeReceived'] == false) {
      return 'Session challenge request failed before authentication. '
          'Check the API Space ID and device connection. $statusNote';
    }
    return 'Session request failed due to an unexpected response or network error. '
        'Check the device connection and push profile configuration. $statusNote';
  }

  void _validateIdentity() {
    if (restartRequired) {
      throw StateError('Restart the app to use the new API space.');
    }
    if (_config.apiSpaceId.trim().isEmpty || _config.userId.trim().isEmpty) {
      throw StateError('Configure an API space and user before enabling push.');
    }
  }

  Future<void> _initializeSdk() async {
    _validateIdentity();
    if (_isInitialized) return;
    _log('Initializing Dotdigital SDK...');
    DotdigitalPush.setChallengeHandler((nonce) async =>
        _config.sharedSecret == null ? null : _config.generateJwt(nonce: nonce));
    if (!await DotdigitalPush.initialize(_config)) {
      throw StateError('SDK initialization failed.');
    }
    _isInitialized = true;
    _initializedApiSpaceId = _config.apiSpaceId;
    _sessionState = await DotdigitalPush.getSessionState();
  }

  Future<void> _recoverSession() async {
    _permissionStatus = await DotdigitalPush.getNotificationPermissionStatus();
    if (_permissionStatus != PushPermissionStatus.authorized) return;
    await _initializeSdk();
    _sessionState = await DotdigitalPush.getSessionState();
    if (_sessionState.isSessionActive && _sessionState.profileId != _config.userId) {
      throw StateError('The active session belongs to another user. End it before continuing.');
    }
    if (!_sessionState.isSessionActive) {
      _log('Starting push session...');
      if (!await DotdigitalPush.startSession()) {
        throw StateError('Session start failed.');
      }
      _sessionState = await DotdigitalPush.getSessionState();
      if (!_sessionState.isSessionActive || _sessionState.profileId != _config.userId) {
        throw StateError('The requested user session could not be verified.');
      }
    } else if (!await DotdigitalPush.registerPushToken()) {
      throw StateError('Push token registration failed.');
    }
    final email = _config.contactEmail?.trim();
    if (email != null && email.isNotEmpty && !isEmailSynced) {
      await _syncEmail(email);
    }
    _sessionState = await DotdigitalPush.getSessionState();
  }

  Future<void> _syncEmail(String email) async {
    _log('Syncing contact email...');
    if (!await DotdigitalPush.updateUserEmail(email)) {
      throw StateError('Email sync failed.');
    }
    _syncedEmail = email.trim().toLowerCase();
    await _saveLifecycle();
  }

  Future<void> _finishOptOut() async {
    await _initializeSdk();
    if (!await DotdigitalPush.endSession()) {
      throw StateError('Could not end the push session.');
    }
    _sessionState = await DotdigitalPush.getSessionState();
    _pushIntent = 'disabled';
    await _saveLifecycle();
    _log('Push session ended.');
  }

  Future<bool> startLifecycle() => _runLifecycle(() async {
    _permissionStatus = await DotdigitalPush.getNotificationPermissionStatus();
    if (isOptOutPending) {
      await _finishOptOut();
    } else if (isPushEnabled) {
      await _recoverSession();
    }
  });

  Future<bool> enablePush() => _runLifecycle(() async {
    if (isOptOutPending) throw StateError('Finish the pending opt-out first.');
    _validateIdentity();
    _pushIntent = 'enabled';
    await _saveLifecycle();
    await _initializeSdk();
    _permissionStatus = await DotdigitalPush.getNotificationPermissionStatus();
    if (_permissionStatus == PushPermissionStatus.notDetermined) {
      await DotdigitalPush.requestNotificationPermissions();
      _permissionStatus = await DotdigitalPush.getNotificationPermissionStatus();
    }
    if (_permissionStatus == PushPermissionStatus.authorized) await _recoverSession();
  });

  Future<bool> endSession() => _runLifecycle(() async {
    _validateIdentity();
    _pushIntent = 'pending';
    await _saveLifecycle();
    await _finishOptOut();
  });

  Future<bool> retryLifecycle() => startLifecycle();

  Future<bool> saveConfiguration(DotdigitalConfig newConfig) => _runLifecycle(() async {
    final identityChanged = _config.apiSpaceId != newConfig.apiSpaceId ||
        _config.userId != newConfig.userId;
    if (identityChanged && !restartRequired && (_isInitialized || isPushEnabled || isOptOutPending)) {
      _pushIntent = 'pending';
      await _saveLifecycle();
      await _finishOptOut();
    }
    final emailChanged = _config.contactEmail?.trim().toLowerCase() !=
        newConfig.contactEmail?.trim().toLowerCase();
    _config = newConfig;
    if (identityChanged) {
      _pushIntent = 'unconfirmed';
      _sessionState = const DotdigitalSessionState(isSessionActive: false);
    }
    if (identityChanged || emailChanged) _syncedEmail = null;
    await _saveConfig();
    await _saveLifecycle();
    if (isPushEnabled) await _recoverSession();
  });

  Future<bool> updateUserEmail(String email) => _runLifecycle(() async {
    if (!isPushEnabled || !_sessionState.isSessionActive) {
      throw StateError('An active push session is required to sync email.');
    }
    await _syncEmail(email);
    _config = DotdigitalConfig(
      apiSpaceId: _config.apiSpaceId,
      sharedSecret: _config.sharedSecret,
      issuer: _config.issuer,
      audience: _config.audience,
      userId: _config.userId,
      contactEmail: email,
      backendAuthUrl: _config.backendAuthUrl,
      apnsEnvironment: _config.apnsEnvironment,
    );
    await _saveConfig();
  });

  Future<void> refreshSessionState() async {
    if (_lifecycleBusy) return;
    try {
      _permissionStatus = await DotdigitalPush.getNotificationPermissionStatus();
      if (isInitialized) _sessionState = await DotdigitalPush.getSessionState();
      notifyListeners();
    } catch (error) {
      _log('Error refreshing lifecycle state: $error');
    }
  }

  /// Simulates an incoming foreground push notification to test in-app toasts and inbox logging.
  void simulateInAppPush({
    required String title,
    required String body,
    String? deepLinkUrl,
    Map<String, dynamic>? customData,
  }) {
    _log('Simulating incoming push: "$title"');
    final item = NotificationHistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      deepLinkUrl: deepLinkUrl,
      customData: customData ?? {},
      rawPayload: {
        'title': title,
        'body': body,
        if (deepLinkUrl != null) 'dd_deepLink': {'url': deepLinkUrl},
        'dd_data': ?customData,
      },
      type: deepLinkUrl != null ? NotificationType.deepLink : NotificationType.standard,
      receivedAt: DateTime.now(),
    );

    _addHistoryItem(item);
    _toastController.add(item);
  }

  /// Simulates a silent data push (`isSilent: true`) without showing a visual alert banner.
  void simulateSilentPush({required Map<String, dynamic> customData}) {
    _log('Simulating silent data push: $customData');
    final item = NotificationHistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Simulated Silent Push',
      body: 'Data payload: ${jsonEncode(customData)}',
      customData: customData,
      rawPayload: {'dd_data': customData},
      type: NotificationType.silentData,
      receivedAt: DateTime.now(),
    );

    _addHistoryItem(item);
  }

  /// Triggers internal deep link navigation for the provided [url] string.
  void triggerDeepLink(
    String url, {
    Map<String, dynamic>? extraData,
    Map<String, dynamic>? rawPayload,
  }) {
    _log('Manually triggering deep link navigation: $url');
    _deepLinkNavigationController.add(
      DeepLinkNavigationEvent(
        url: url,
        extraData: extraData,
        rawPayload: rawPayload,
      ),
    );
  }

  /// Internal helper to insert an item into history, cap max items, and persist to storage.
  void _addHistoryItem(NotificationHistoryItem item) {
    _history.insert(0, item);
    if (_history.length > 50) _history.removeLast();
    _saveHistory();
    notifyListeners();
  }

  /// Marks a specific notification in history as read.
  void markAsRead(String id) {
    final index = _history.indexWhere((element) => element.id == id);
    if (index != -1) {
      _history[index].isRead = true;
      _saveHistory();
      notifyListeners();
    }
  }

  /// Clears all stored notification history.
  void clearHistory() {
    _history.clear();
    _saveHistory();
    notifyListeners();
  }

  /// Clears the activity log list.
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Loads configuration from local persistent storage (`SharedPreferences`).
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('dotdigital_config');
    if (jsonStr != null) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        _config = DotdigitalConfig.fromMap(map);
      } catch (_) {}
    }
  }

  /// Saves current configuration to local persistent storage (`SharedPreferences`).
  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dotdigital_config', jsonEncode(_config.toMap()));
  }

  Future<void> _loadLifecycle() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('push_lifecycle');
    if (saved == null) return;
    try {
      final state = jsonDecode(saved) as Map<String, dynamic>;
      if (state['apiSpaceId'] != _config.apiSpaceId || state['userId'] != _config.userId) return;
      final intent = state['intent'];
      if (intent == 'enabled' || intent == 'disabled' || intent == 'pending') {
        _pushIntent = intent as String;
      }
      _syncedEmail = state['syncedEmail'] as String?;
    } catch (_) {
      _pushIntent = 'unconfirmed';
    }
  }

  Future<void> _saveLifecycle() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('push_lifecycle', jsonEncode({
      'apiSpaceId': _config.apiSpaceId,
      'userId': _config.userId,
      'intent': _pushIntent,
      'syncedEmail': _syncedEmail,
    }));
  }

  /// Loads stored notification history from persistent storage.
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notification_history') ?? [];
    _history.clear();
    for (final str in list) {
      try {
        _history.add(NotificationHistoryItem.fromJson(str));
      } catch (_) {}
    }
  }

  /// Saves notification history list to persistent storage.
  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _history.map((e) => e.toJson()).toList();
    await prefs.setStringList('notification_history', list);
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    _tapSub?.cancel();
    _silentSub?.cancel();
    _pushTokenSub?.cancel();
    _toastController.close();
    _deepLinkNavigationController.close();
    super.dispose();
  }
}

/// Event emitted when a push notification tap or trigger requests opening a URL or deep link.
class DeepLinkNavigationEvent {
  final String url;
  final Map<String, dynamic>? extraData;
  final Map<String, dynamic>? rawPayload;

  const DeepLinkNavigationEvent({
    required this.url,
    this.extraData,
    this.rawPayload,
  });
}
