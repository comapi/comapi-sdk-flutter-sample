import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/notification_history_item.dart';
import '../services/notification_service.dart';
import '../theme/dotdigital_brand.dart';

// ============================================================================
// NOTIFICATION INBOX & REVIEW LIST SCREEN
// ============================================================================
// HIGH LEVEL NARRATIVE:
// Provides a persistent notification center / review inbox for mobile users:
//
// 1. Unified Message Log: Captures and stores foreground alerts, notifications
//    tapped from system tray, and silent background data pushes (`dd_data`).
// 2. Inspection & Debugging: Tapping any message opens a dialog displaying:
//    - Deep Link target URL (if present).
//    - Dotdigital Click Tracking status (`isClickRecorded` / `isDeepLinkCalled`).
//    - Formatted raw JSON payload directly as received from Apple/Google.
// 3. Re-Trigger Deep Link: Users can tap "Open Deep Link" directly from the review
//    item to navigate to the targeted screen at any time.
// ============================================================================

class NotificationInboxScreen extends StatelessWidget {
  final void Function(
    String deepLinkUrl, {
    Map<String, dynamic>? extraData,
    Map<String, dynamic>? rawPayload,
  })? onDeepLinkTap;

  const NotificationInboxScreen({super.key, this.onDeepLinkTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NotificationService(),
      builder: (context, _) {
        final history = NotificationService().history;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Notification Inbox / History'),
            backgroundColor: DotdigitalBrand.inkBlack,
            foregroundColor: DotdigitalBrand.white,
            actions: [
              if (history.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: DotdigitalBrand.brightSand,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        title: Text('Clear Inbox', style: DotdigitalBrand.headerStyle(fontSize: 20)),
                        content: Text(
                          'Are you sure you want to clear all notification history?',
                          style: DotdigitalBrand.bodyStyle(fontSize: 13),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel', style: TextStyle(color: DotdigitalBrand.inkBlack)),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              NotificationService().clearHistory();
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: DotdigitalBrand.coralStep1,
                              foregroundColor: DotdigitalBrand.white,
                            ),
                            child: const Text('Clear All'),
                          ),
                        ],
                      ),
                    );
                  },
                  tooltip: 'Clear Inbox',
                ),
            ],
          ),
          body: history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inbox_outlined, size: 72, color: DotdigitalBrand.midSand),
                      const SizedBox(height: 16),
                      Text(
                        'Inbox is Empty',
                        style: DotdigitalBrand.headerStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: Text(
                          'Push messages, deep links, and silent data received while the app is running or tapped from background will appear here.',
                          textAlign: TextAlign.center,
                          style: DotdigitalBrand.bodyStyle(
                            color: DotdigitalBrand.charcoal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = history[index];
                    return _NotificationCard(
                      item: item,
                      onDeepLinkTap: onDeepLinkTap,
                      onShowDetails: () => _showDetailsDialog(context, item),
                    );
                  },
                ),
        );
      },
    );
  }

  /// Displays an inspection dialog detailing the notification type, tracking status, and raw JSON payload.
  void _showDetailsDialog(BuildContext context, NotificationHistoryItem item) {
    NotificationService().markAsRead(item.id);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DotdigitalBrand.brightSand,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: DotdigitalBrand.signalPink,
                shape: BoxShape.circle,
              ),
              child: Icon(
                item.type == NotificationType.deepLink
                    ? Icons.link
                    : item.type == NotificationType.silentData
                        ? Icons.sync_alt
                        : Icons.notifications,
                color: DotdigitalBrand.inkBlack,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                style: DotdigitalBrand.headerStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.deepLinkUrl != null) ...[
                  Text('DEEP LINK URL', style: DotdigitalBrand.eyebrowStyle(fontSize: 10)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: DotdigitalBrand.softSand,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: DotdigitalBrand.warmSand),
                    ),
                    child: SelectableText(
                      item.deepLinkUrl!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: DotdigitalBrand.inkBlack,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text('ANALYTICS / CLICK TRACKING', style: DotdigitalBrand.eyebrowStyle(fontSize: 10)),
                const SizedBox(height: 6),
                Text('Click Recorded: ${item.isClickRecorded}', style: DotdigitalBrand.bodyStyle(fontSize: 13)),
                Text('Deep Link Launched: ${item.isDeepLinkCalled}', style: DotdigitalBrand.bodyStyle(fontSize: 13)),
                const SizedBox(height: 14),
                Text('RAW JSON PAYLOAD', style: DotdigitalBrand.eyebrowStyle(fontSize: 10)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DotdigitalBrand.inkBlack,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(item.rawPayload),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: DotdigitalBrand.signalPink,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (item.deepLinkUrl != null && item.deepLinkUrl!.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                onDeepLinkTap?.call(
                  item.deepLinkUrl!,
                  extraData: item.customData,
                  rawPayload: item.rawPayload,
                );
              },
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open Deep Link'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DotdigitalBrand.neon,
                foregroundColor: DotdigitalBrand.inkBlack,
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: DotdigitalBrand.inkBlack)),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationHistoryItem item;
  final void Function(
    String deepLinkUrl, {
    Map<String, dynamic>? extraData,
    Map<String, dynamic>? rawPayload,
  })? onDeepLinkTap;
  final VoidCallback onShowDetails;

  const _NotificationCard({
    required this.item,
    this.onDeepLinkTap,
    required this.onShowDetails,
  });

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    IconData typeIcon;
    String typeLabel;

    switch (item.type) {
      case NotificationType.deepLink:
        badgeColor = DotdigitalBrand.neon;
        typeIcon = Icons.link;
        typeLabel = 'DEEP LINK';
        break;
      case NotificationType.silentData:
        badgeColor = DotdigitalBrand.warmSand;
        typeIcon = Icons.sync_alt;
        typeLabel = 'SILENT PUSH';
        break;
      case NotificationType.standard:
        badgeColor = DotdigitalBrand.signalPink;
        typeIcon = Icons.notifications;
        typeLabel = 'STANDARD PUSH';
        break;
    }

    final timeStr = DateFormat('MMM d, HH:mm:ss').format(item.receivedAt);
    final hasUrl = item.deepLinkUrl != null && item.deepLinkUrl!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: DotdigitalBrand.softSand,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DotdigitalBrand.warmSand, width: 1.5),
      ),
      child: InkWell(
        onTap: () {
          NotificationService().markAsRead(item.id);
          if (hasUrl && onDeepLinkTap != null) {
            onDeepLinkTap!(
              item.deepLinkUrl!,
              extraData: item.customData,
              rawPayload: item.rawPayload,
            );
          } else {
            onShowDetails();
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(typeIcon, size: 12, color: DotdigitalBrand.inkBlack),
                        const SizedBox(width: 5),
                        Text(
                          typeLabel,
                          style: DotdigitalBrand.eyebrowStyle(
                            fontSize: 9,
                            color: DotdigitalBrand.inkBlack,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeStr,
                    style: const TextStyle(color: DotdigitalBrand.coolGray, fontSize: 11),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.data_object, size: 18, color: DotdigitalBrand.inkBlack),
                    tooltip: 'Inspect Raw Payload',
                    onPressed: onShowDetails,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                style: DotdigitalBrand.headerStyle(fontSize: 17),
              ),
              if (item.body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: DotdigitalBrand.bodyStyle(color: DotdigitalBrand.charcoal, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (item.deepLinkUrl != null && item.deepLinkUrl!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: DotdigitalBrand.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: DotdigitalBrand.warmSand),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.turn_right, size: 14, color: DotdigitalBrand.inkBlack),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.deepLinkUrl!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: DotdigitalBrand.inkBlack,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
