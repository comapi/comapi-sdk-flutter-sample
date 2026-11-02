import 'dart:convert';
import 'package:crypto/crypto.dart';

enum PushPermissionStatus { unknown, notDetermined, denied, authorized }

// ============================================================================
// DOTDIGITAL MOBILE PUSH INTEGRATION ARCHITECTURE
// ============================================================================
// Dotdigital Mobile Push is built on the Comapi Foundation SDK architecture.
//
// HIGH-LEVEL NARRATIVE:
// 1. App initializes Comapi client using an `apiSpaceId` issued by Dotdigital.
// 2. When starting a push session, the SDK issues an authentication challenge
//    containing a cryptographic `nonce`.
// 3. The client application must respond to this challenge with a signed JWT
//    (HS256) containing `iss`, `aud`, `sub` (user/device ID), `nonce`, `iat`, and `exp`.
// 4. Dotdigital validates the token and registers the device's push token (FCM / APNs).
// 5. AUDIENCE DISCOVERY: To make the contact reachable in Dotdigital Marketing
//    (and populate the `PUSHOPTIN_xxx` field), the app MUST patch the user's
//    profile with an email address.
// 6. When messages arrive:
//    - Foreground: Handled by app code; system does not automatically show alerts.
//    - Background/Tapped: The intent/notification response is passed to the SDK
//      (`handlePushNotification` on Android / `handleNotificationResponse` on iOS)
//      to fire Dotdigital click tracking analytics and resolve deep links (`ddexample:`).
//    - Silent Pushes: Background data-only payloads (`dd_data`) without visual alerts.
// ============================================================================

/// Configuration for the Dotdigital Mobile Push integration.
class DotdigitalConfig {
  /// The API Space ID from Dotdigital Marketing Push Notification Profile.
  final String apiSpaceId;

  /// The Shared Secret used to sign JWTs (HS256).
  ///
  /// ⚠️ CRITICAL SECURITY WARNING:
  /// NEVER embed or hardcode production shared secrets directly inside a mobile app binary!
  /// Client-side signing is provided here strictly for example purposes, local testing,
  /// and documentation validation. In production applications, request signed tokens from
  /// an authenticated backend server endpoint (e.g. using [backendAuthUrl]).
  final String? sharedSecret;

  /// The Issuer (iss) claim for the JWT, e.g. https://api.comapi.com/defaultauth
  final String issuer;

  /// The Audience (aud) claim for the JWT, e.g. https://api.comapi.com
  final String audience;

  /// The unique consistent subject (sub) claim representing the app user or device ID.
  final String userId;

  /// The user's email address used to discover and link the contact in Dotdigital Marketing.
  final String? contactEmail;

  /// Optional backend URL to retrieve JWTs instead of signing on-device.
  final String? backendAuthUrl;

  /// Optional APNs environment override ('development' or 'production').
  final String? apnsEnvironment;

  const DotdigitalConfig({
    required this.apiSpaceId,
    required this.userId,
    this.sharedSecret,
    this.issuer = 'https://api.comapi.com/defaultauth',
    this.audience = 'https://api.comapi.com',
    this.contactEmail,
    this.backendAuthUrl,
    this.apnsEnvironment,
  });

  /// Serializes the configuration into a map for platform channel transfer.
  Map<String, dynamic> toMap() {
    return {
      'apiSpaceId': apiSpaceId,
      'sharedSecret': sharedSecret,
      'issuer': issuer,
      'audience': audience,
      'userId': userId,
      'contactEmail': contactEmail,
      'backendAuthUrl': backendAuthUrl,
      'apnsEnvironment': apnsEnvironment,
    };
  }

  /// Deserializes a configuration map into a [DotdigitalConfig] instance.
  factory DotdigitalConfig.fromMap(Map<String, dynamic> map) {
    return DotdigitalConfig(
      apiSpaceId: map['apiSpaceId'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      sharedSecret: map['sharedSecret'] as String?,
      issuer: map['issuer'] as String? ?? 'https://api.comapi.com/defaultauth',
      audience: map['audience'] as String? ?? 'https://api.comapi.com',
      contactEmail: map['contactEmail'] as String?,
      backendAuthUrl: map['backendAuthUrl'] as String?,
      apnsEnvironment: map['apnsEnvironment'] as String?,
    );
  }

  /// Helper to generate a compliant JWT for Dotdigital authentication challenge.
  /// Follows Dotdigital docs: HS256, typ: JWT, sub, iss, aud, nonce, iat, exp in seconds.
  ///
  /// ⚠️ SECURITY WARNING:
  /// Generating JWTs on the client device requires exposing the Shared Secret inside the app.
  /// This method is intended solely for local rapid prototyping, integration testing, and documentation
  /// validation as demonstrated in the Dotdigital developer guide samples.
  /// Production applications should never bundle the shared secret; they should fetch signed tokens from a backend.
  String generateJwt({required String nonce}) {
    if (sharedSecret == null || sharedSecret!.isEmpty) {
      throw StateError('Cannot generate JWT locally without sharedSecret');
    }

    final header = {'typ': 'JWT', 'alg': 'HS256'};
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final expSeconds = nowSeconds + (30 * 24 * 60 * 60); // 30 days

    final payload = {
      'nonce': nonce,
      'sub': userId,
      'iss': issuer,
      'aud': audience,
      'iat': nowSeconds,
      'exp': expSeconds,
    };

    String base64UrlEncode(String input) {
      return base64Url
          .encode(utf8.encode(input))
          .replaceAll('=', '');
    }

    final encodedHeader = base64UrlEncode(jsonEncode(header));
    final encodedPayload = base64UrlEncode(jsonEncode(payload));
    final signingInput = '$encodedHeader.$encodedPayload';

    final hmac = Hmac(sha256, utf8.encode(sharedSecret!));
    final digest = hmac.convert(utf8.encode(signingInput));
    final encodedSignature = base64Url.encode(digest.bytes).replaceAll('=', '');

    return '$signingInput.$encodedSignature';
  }
}

/// Represents an incoming push notification received while app is in foreground.
class PushNotification {
  final String? title;
  final String? body;
  final String? deepLinkUrl;
  final Map<String, dynamic>? customData;
  final Map<String, dynamic> rawPayload;
  final DateTime timestamp;

  /// Creates a [PushNotification] representing an incoming push payload.
  PushNotification({
    this.title,
    this.body,
    this.deepLinkUrl,
    this.customData,
    required this.rawPayload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Deserializes a native notification map into a [PushNotification].
  factory PushNotification.fromMap(Map<String, dynamic> map) {
    return PushNotification(
      title: map['title'] as String?,
      body: map['body'] as String?,
      deepLinkUrl: map['deepLinkUrl'] as String?,
      customData: map['customData'] != null
          ? Map<String, dynamic>.from(map['customData'] as Map)
          : null,
      rawPayload: map['rawPayload'] != null
          ? Map<String, dynamic>.from(map['rawPayload'] as Map)
          : {},
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now(),
    );
  }

  /// Converts the notification into a map for storage or transmission.
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'deepLinkUrl': deepLinkUrl,
      'customData': customData,
      'rawPayload': rawPayload,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}

/// Represents a notification tap / click event from background or launcher.
class PushTapEvent {
  final String? url;
  final Map<String, dynamic>? customData;
  final bool isClickRecorded;
  final bool isDeepLinkCalled;
  final bool isDdOriginated;
  final Map<String, dynamic> rawPayload;
  final DateTime timestamp;

  /// Creates a [PushTapEvent] representing a user notification click.
  PushTapEvent({
    this.url,
    this.customData,
    required this.isClickRecorded,
    required this.isDeepLinkCalled,
    required this.isDdOriginated,
    required this.rawPayload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Deserializes a native tap response map into a [PushTapEvent].
  factory PushTapEvent.fromMap(Map<String, dynamic> map) {
    return PushTapEvent(
      url: map['url'] as String?,
      customData: map['customData'] != null
          ? Map<String, dynamic>.from(map['customData'] as Map)
          : null,
      isClickRecorded: map['isClickRecorded'] as bool? ?? false,
      isDeepLinkCalled: map['isDeepLinkCalled'] as bool? ?? false,
      isDdOriginated: map['isDdOriginated'] as bool? ?? false,
      rawPayload: map['rawPayload'] != null
          ? Map<String, dynamic>.from(map['rawPayload'] as Map)
          : {},
      timestamp: DateTime.now(),
    );
  }
}

/// Represents a silent background data push (content-available: 1 / FCM data-only).
class SilentPushEvent {
  final Map<String, dynamic>? customData;
  final Map<String, dynamic> rawPayload;
  final DateTime timestamp;

  /// Creates a [SilentPushEvent] representing a background data update.
  SilentPushEvent({
    this.customData,
    required this.rawPayload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Deserializes a native silent push map into a [SilentPushEvent].
  factory SilentPushEvent.fromMap(Map<String, dynamic> map) {
    return SilentPushEvent(
      customData: map['customData'] != null
          ? Map<String, dynamic>.from(map['customData'] as Map)
          : null,
      rawPayload: map['rawPayload'] != null
          ? Map<String, dynamic>.from(map['rawPayload'] as Map)
          : {},
      timestamp: DateTime.now(),
    );
  }
}

/// Status of the active Comapi / Dotdigital SDK session.
class DotdigitalSessionState {
  final bool isSessionActive;
  final String? profileId;
  final String? deviceId;
  final String? pushToken;
  final String? currentEmail;

  /// Creates a [DotdigitalSessionState] snapshot.
  const DotdigitalSessionState({
    required this.isSessionActive,
    this.profileId,
    this.deviceId,
    this.pushToken,
    this.currentEmail,
  });

  /// Deserializes a native session status map into a [DotdigitalSessionState].
  factory DotdigitalSessionState.fromMap(Map<String, dynamic> map) {
    return DotdigitalSessionState(
      isSessionActive: map['isSessionActive'] as bool? ?? false,
      profileId: map['profileId'] as String?,
      deviceId: map['deviceId'] as String?,
      pushToken: map['pushToken'] as String?,
      currentEmail: map['currentEmail'] as String?,
    );
  }
}
