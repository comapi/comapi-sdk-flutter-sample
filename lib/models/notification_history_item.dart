import 'dart:convert';

/// Classification of push notifications received by the application.
enum NotificationType {
  /// Standard visual notification with alert title and body.
  standard,

  /// Push carrying a deep link target (e.g. `ddexample://product/:id` or web URL).
  deepLink,

  /// Background push with `isSilent: true` delivering custom data (`dd_data`) without visual alert.
  silentData,
}

/// Persistent record representing a push notification stored in the local inbox.
class NotificationHistoryItem {
  final String id;
  final String title;
  final String body;
  final String? deepLinkUrl;
  final Map<String, dynamic> customData;
  final Map<String, dynamic> rawPayload;
  final NotificationType type;
  final DateTime receivedAt;
  final bool isClickRecorded;
  final bool isDeepLinkCalled;
  bool isRead;

  /// Creates a [NotificationHistoryItem] for inbox review and logging.
  NotificationHistoryItem({
    required this.id,
    required this.title,
    required this.body,
    this.deepLinkUrl,
    this.customData = const {},
    this.rawPayload = const {},
    required this.type,
    required this.receivedAt,
    this.isClickRecorded = false,
    this.isDeepLinkCalled = false,
    this.isRead = false,
  });

  /// Serializes the history item into a JSON-compatible map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'deepLinkUrl': deepLinkUrl,
      'customData': customData,
      'rawPayload': rawPayload,
      'type': type.name,
      'receivedAt': receivedAt.toIso8601String(),
      'isClickRecorded': isClickRecorded,
      'isDeepLinkCalled': isDeepLinkCalled,
      'isRead': isRead,
    };
  }

  /// Deserializes a history item from a map.
  factory NotificationHistoryItem.fromMap(Map<String, dynamic> map) {
    NotificationType parsedType;
    switch (map['type']) {
      case 'deepLink':
        parsedType = NotificationType.deepLink;
        break;
      case 'silentData':
        parsedType = NotificationType.silentData;
        break;
      default:
        parsedType = NotificationType.standard;
    }

    return NotificationHistoryItem(
      id: map['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      deepLinkUrl: map['deepLinkUrl'] as String?,
      customData: map['customData'] != null
          ? Map<String, dynamic>.from(map['customData'] as Map)
          : {},
      rawPayload: map['rawPayload'] != null
          ? Map<String, dynamic>.from(map['rawPayload'] as Map)
          : {},
      type: parsedType,
      receivedAt: map['receivedAt'] != null
          ? DateTime.parse(map['receivedAt'] as String)
          : DateTime.now(),
      isClickRecorded: map['isClickRecorded'] as bool? ?? false,
      isDeepLinkCalled: map['isDeepLinkCalled'] as bool? ?? false,
      isRead: map['isRead'] as bool? ?? false,
    );
  }

  /// Serializes the item to a JSON string for persistent storage.
  String toJson() => jsonEncode(toMap());

  /// Deserializes a history item from a JSON string.
  factory NotificationHistoryItem.fromJson(String source) =>
      NotificationHistoryItem.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
