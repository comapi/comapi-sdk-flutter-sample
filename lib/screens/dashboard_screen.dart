import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dotdigital_push/dotdigital_push.dart';
import '../services/notification_service.dart';
import '../theme/dotdigital_brand.dart';
import 'config_screen.dart';
import 'notification_inbox_screen.dart';

// ============================================================================
// DASHBOARD SCREEN - STATUS, LIFECYCLE & TEST CONSOLE
// ============================================================================
// HIGH LEVEL NARRATIVE:
// Provides an interactive control panel to guide developers and testers through
// the four key stages of Dotdigital Push channel onboarding:
//
// 1. Status Monitoring: Shows initialization state, session active status,
//    profile ID (JWT sub claim), linked email (for contact discovery), and
//    the registered device push token (FCM / APNs) with tap-to-copy.
// 2. Lifecycle Actions:
//    - Initialize: Configures native Comapi SDK with API Space ID.
//    - Permissions: Requests POST_NOTIFICATIONS (Android 13+) / UNUserNotificationCenter.
//    - Start Session: Fulfills JWT challenge and creates push session.
//    - Sync Email: Patches push profile with eTag to populate PUSHOPTIN_xxx in Dotdigital.
//    - End Session: Unregisters device push token and tears down session.
// 3. Test & Validation Triggers:
//    Allows triggering in-app toast alerts, deep links (`ddexample://product/42`,
//    `ddexample://promo`), and silent data pushes (`dd_data`) without waiting
//    for external campaign dispatch.
// 4. Live Activity Log: Real-time scrolling console showing native events.
//
// ⚠️ SECURITY WARNING:
// Client-side JWT signing using the Shared Secret is for local testing and example
// purposes only. In production, tokens must be signed on an authenticated backend server.
// ============================================================================

class DashboardScreen extends StatefulWidget {
  final void Function(
    String deepLinkUrl, {
    Map<String, dynamic>? extraData,
    Map<String, dynamic>? rawPayload,
  })? onDeepLinkTap;

  const DashboardScreen({super.key, this.onDeepLinkTap});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final NotificationService _service = NotificationService();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final config = _service.config;
        final session = _service.sessionState;
        final unreadCount = _service.history.where((e) => !e.isRead).length;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    DotdigitalBrand.pinkLogoAsset,
                    height: 28,
                    width: 28,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Dotdigital',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: DotdigitalBrand.fontHeadline,
                      fontSize: 19,
                      fontWeight: FontWeight.w500,
                      color: DotdigitalBrand.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: const BoxDecoration(
                    color: DotdigitalBrand.signalPink,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  child: Text(
                    'PUSH SDK',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DotdigitalBrand.eyebrowStyle(
                      fontSize: 9,
                      color: DotdigitalBrand.inkBlack,
                    ),
                  ),
                  ),
                ),
              ],
            ),
            backgroundColor: DotdigitalBrand.inkBlack,
            foregroundColor: DotdigitalBrand.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ConfigScreen()),
                  );
                },
                tooltip: 'Credentials & Config',
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.inbox_outlined),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NotificationInboxScreen(
                            onDeepLinkTap: widget.onDeepLinkTap,
                          ),
                        ),
                      );
                    },
                    tooltip: 'Notification Inbox',
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: DotdigitalBrand.neon,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            color: DotdigitalBrand.inkBlack,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: DotdigitalBrand.inkBlack))
              : RefreshIndicator(
                  color: DotdigitalBrand.inkBlack,
                  onRefresh: () => _service.refreshSessionState(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MARKETING MADE HUMAN',
                          style: DotdigitalBrand.eyebrowStyle(
                            fontSize: 11,
                            color: DotdigitalBrand.darkSand,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Flutter push example app',
                          style: DotdigitalBrand.headlineStyle(fontSize: 26),
                        ),
                        const SizedBox(height: 16),
                        _buildStatusCard(config, session),
                        const SizedBox(height: 24),
                        Text(
                          'ONBOARDING FLOW',
                          style: DotdigitalBrand.eyebrowStyle(
                            fontSize: 10,
                            color: DotdigitalBrand.darkSand,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Lifecycle Actions',
                          style: DotdigitalBrand.headerStyle(fontSize: 20),
                        ),
                        const SizedBox(height: 12),
                        _buildActionButtons(session),
                        const SizedBox(height: 26),
                        Text(
                          'SANDBOX VALIDATION',
                          style: DotdigitalBrand.eyebrowStyle(
                            fontSize: 10,
                            color: DotdigitalBrand.darkSand,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Test & Validation Triggers',
                          style: DotdigitalBrand.headerStyle(fontSize: 20),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Simulate push messages, deep links (ddexample:), and silent data to test in-app behavior without waiting for a server send:',
                          style: DotdigitalBrand.bodyStyle(
                            fontSize: 13,
                            color: DotdigitalBrand.charcoal,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTestTriggers(),
                        const SizedBox(height: 26),
                        Row(
                          children: [
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DIAGNOSTICS',
                                  style: DotdigitalBrand.eyebrowStyle(
                                    fontSize: 10,
                                    color: DotdigitalBrand.darkSand,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Live Activity Log',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DotdigitalBrand.headerStyle(fontSize: 20),
                                ),
                              ],
                            )),
                            IconButton(
                              tooltip: 'Copy logs',
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: _service.logs.isEmpty
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: _service.logs.join('\n')),
                                      );
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Activity logs copied to clipboard!')),
                                      );
                                    },
                            ),
                            TextButton.icon(
                              onPressed: () => _service.clearLogs(),
                              icon: const Icon(Icons.clear_all, size: 16, color: DotdigitalBrand.inkBlack),
                              label: Text(
                                'Clear',
                                style: TextStyle(
                                  fontFamily: DotdigitalBrand.fontBody,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: DotdigitalBrand.inkBlack,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildLogConsole(),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  /// Builds the summary card displaying SDK status, session state, and push token.
  Widget _buildStatusCard(DotdigitalConfig config, DotdigitalSessionState session) {
    return Container(
      decoration: BoxDecoration(
        color: DotdigitalBrand.softSand,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: DotdigitalBrand.warmSand, width: 1.5),
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DotdigitalBrand.signalPink,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.cell_tower, color: DotdigitalBrand.inkBlack, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CHANNEL STATUS',
                      style: DotdigitalBrand.eyebrowStyle(
                        fontSize: 9,
                        color: DotdigitalBrand.darkSand,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Dotdigital Mobile Push',
                      style: DotdigitalBrand.headerStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'API Space: ${config.apiSpaceId.isNotEmpty ? config.apiSpaceId : "Not set"}',
                      style: DotdigitalBrand.bodyStyle(
                        fontSize: 12,
                        color: DotdigitalBrand.coolGray,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 26, color: DotdigitalBrand.warmSand),
          _buildStatusRow(
            label: 'SDK Initialized',
            value: _service.isInitialized ? 'Ready' : 'Not Initialized',
            isOk: _service.isInitialized,
          ),
          const SizedBox(height: 10),
          _buildStatusRow(
            label: 'Session Active',
            value: session.isSessionActive && !_service.hasMatchingSession ? 'Different user' : _service.hasMatchingSession ? 'Active' : 'Inactive',
            isOk: _service.hasMatchingSession,
          ),
          const SizedBox(height: 10),
          _buildStatusRow(
            label: 'Push Profile ID',
            value: session.profileId ?? config.userId,
            isMono: true,
          ),
          const SizedBox(height: 10),
          _buildStatusRow(
            label: 'Contact Email',
            value: config.contactEmail ?? 'No email linked',
            isOk: _service.isEmailSynced,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  'Device Push Token:',
                  style: DotdigitalBrand.bodyStyle(
                    fontSize: 13,
                    color: DotdigitalBrand.darkSand,
                  ),
                ),
              ),
              Expanded(
                child: session.pushToken != null
                    ? InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: session.pushToken!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Push token copied to clipboard!')),
                          );
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: DotdigitalBrand.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: DotdigitalBrand.warmSand),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  session.pushToken!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: DotdigitalBrand.inkBlack,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.copy, size: 13, color: DotdigitalBrand.inkBlack),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: DotdigitalBrand.goldStep4,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Pending / Unregistered',
                          style: TextStyle(
                            fontSize: 11,
                            color: DotdigitalBrand.inkBlack,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Helper to render a labeled key-value status row with optional status icon.
  Widget _buildStatusRow({
    required String label,
    required String value,
    bool? isOk,
    bool isMono = false,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: DotdigitalBrand.bodyStyle(
              fontSize: 13,
              color: DotdigitalBrand.darkSand,
            ),
          ),
        ),
        if (isOk != null)
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isOk ? DotdigitalBrand.neon : DotdigitalBrand.warmSand,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isOk ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 13,
                    color: DotdigitalBrand.inkBlack,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DotdigitalBrand.inkBlack,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: isMono ? 'monospace' : DotdigitalBrand.fontBody,
                color: DotdigitalBrand.inkBlack,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _buildActionButtons(DotdigitalSessionState session) {
    final service = _service;
    final permission = switch (service.permissionStatus) {
      PushPermissionStatus.authorized => 'Granted',
      PushPermissionStatus.denied => 'Disabled',
      PushPermissionStatus.notDetermined => 'Not requested',
      PushPermissionStatus.unknown => 'Unknown',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusRow(label: 'SDK', value: service.isInitialized ? 'Initialized' : 'Not initialized'),
        const SizedBox(height: 8),
        _buildStatusRow(label: 'Permission', value: permission),
        const SizedBox(height: 8),
        _buildStatusRow(label: 'Session', value: service.isOptOutPending ? 'Opt-out pending' : session.isSessionActive && !service.hasMatchingSession ? 'Different user' : service.hasMatchingSession ? 'Active' : 'Inactive'),
        const SizedBox(height: 8),
        _buildStatusRow(label: 'Email sync', value: service.isEmailSynced ? 'Synced' : 'Not synced'),
        if (service.restartRequired) ...[
          const SizedBox(height: 12),
          Text('Restart the app to use the new API space.',
              style: DotdigitalBrand.bodyStyle(color: DotdigitalBrand.coralStep1, fontSize: 13)),
        ],
        if (service.lifecycleBusy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (service.lifecycleError != null) ...[
          const SizedBox(height: 12),
          Text(service.lifecycleError!, style: DotdigitalBrand.bodyStyle(color: DotdigitalBrand.coralStep1, fontSize: 13)),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (service.isOptOutPending)
              ElevatedButton.icon(
                onPressed: service.lifecycleBusy ? null : () => service.retryLifecycle(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry opt-out'),
              )
            else if (!service.isPushEnabled)
              ElevatedButton.icon(
                onPressed: service.lifecycleBusy || service.restartRequired ? null : () => service.enablePush(),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Enable push'),
              )
            else if (service.permissionStatus == PushPermissionStatus.denied)
              ElevatedButton.icon(
                onPressed: service.lifecycleBusy ? null : () => DotdigitalPush.openNotificationSettings(),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Notification settings'),
              )
            else if (service.permissionStatus == PushPermissionStatus.notDetermined)
              ElevatedButton.icon(
                onPressed: service.lifecycleBusy ? null : () => service.enablePush(),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Enable notifications'),
              )
            else if (service.lifecycleError != null || !service.hasMatchingSession)
              ElevatedButton.icon(
                onPressed: service.lifecycleBusy ? null : () => service.retryLifecycle(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            if (service.isPushEnabled && service.hasMatchingSession)
              OutlinedButton.icon(
                onPressed: service.lifecycleBusy ? null : _showEmailDialog,
                icon: const Icon(Icons.mail_outline),
                label: Text(service.isEmailSynced ? 'Update email' : 'Sync email'),
              ),
            if (service.isPushEnabled)
              OutlinedButton.icon(
                onPressed: service.lifecycleBusy ? null : () => service.endSession(),
                icon: const Icon(Icons.stop),
                label: const Text('End session / Opt out'),
              ),
          ],
        ),
      ],
    );
  }

  /// Builds action chips to simulate in-app pushes, deep links, and silent data payloads.
  Widget _buildTestTriggers() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          backgroundColor: DotdigitalBrand.signalPink,
          side: const BorderSide(color: DotdigitalBrand.inkBlack, width: 1),
          shape: const StadiumBorder(),
          avatar: const Icon(Icons.notifications, size: 16, color: DotdigitalBrand.inkBlack),
          label: const Text(
            'Foreground Toast',
            style: TextStyle(
              color: DotdigitalBrand.inkBlack,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          onPressed: () {
            _service.simulateInAppPush(
              title: 'Flash Sale Alert! 🏷️',
              body: 'Exclusive discounts just launched for VIP members.',
            );
          },
        ),
        ActionChip(
          backgroundColor: DotdigitalBrand.warmSand,
          side: const BorderSide(color: DotdigitalBrand.inkBlack, width: 1),
          shape: const StadiumBorder(),
          avatar: const Icon(Icons.link, size: 16, color: DotdigitalBrand.inkBlack),
          label: const Text(
            'Deep Link (Product 42)',
            style: TextStyle(
              color: DotdigitalBrand.inkBlack,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          onPressed: () {
            _service.simulateInAppPush(
              title: 'New Product Arrival 👟',
              body: 'Tap to view the featured sneaker release.',
              deepLinkUrl: 'ddexample://product/42',
              customData: {'productId': '42', 'campaign': 'spring_launch'},
            );
          },
        ),
        ActionChip(
          backgroundColor: DotdigitalBrand.neon,
          side: const BorderSide(color: DotdigitalBrand.inkBlack, width: 1),
          shape: const StadiumBorder(),
          avatar: const Icon(Icons.local_offer, size: 16, color: DotdigitalBrand.inkBlack),
          label: const Text(
            'Deep Link (Promo)',
            style: TextStyle(
              color: DotdigitalBrand.inkBlack,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          onPressed: () {
            _service.simulateInAppPush(
              title: 'Special 25% Coupon! 🎉',
              body: 'Tap to view and claim your promo code.',
              deepLinkUrl: 'ddexample://promo',
              customData: {'promoCode': 'DOTPUSH25'},
            );
          },
        ),
        ActionChip(
          backgroundColor: DotdigitalBrand.softSand,
          side: const BorderSide(color: DotdigitalBrand.inkBlack, width: 1),
          shape: const StadiumBorder(),
          avatar: const Icon(Icons.sync_alt, size: 16, color: DotdigitalBrand.inkBlack),
          label: const Text(
            'Silent Push (dd_data)',
            style: TextStyle(
              color: DotdigitalBrand.inkBlack,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          onPressed: () {
            _service.simulateSilentPush(
              customData: {
                'syncAction': 'REFRESH_CART',
                'cacheExpiry': DateTime.now().millisecondsSinceEpoch + 3600000,
                'silentOrigin': 'Dotdigital Program Builder',
              },
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Silent push received and added to history without alert.'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Builds a dark monospace console widget displaying real-time activity logs.
  Widget _buildLogConsole() {
    final logs = _service.logs;

    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: DotdigitalBrand.inkBlack,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DotdigitalBrand.charcoal, width: 1.5),
      ),
      padding: const EdgeInsets.all(14),
      child: logs.isEmpty
          ? const Center(
              child: Text(
                'Activity log will display here...',
                style: TextStyle(color: DotdigitalBrand.coolGray, fontSize: 12),
              ),
            )
          : ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text(
                    logs[index],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: DotdigitalBrand.signalPink,
                    ),
                  ),
                );
              },
            ),
    );
  }

  /// Wraps asynchronous operations with loading state and UI error handling.
  void _handleAction(Future<dynamic> Function() action) async {
    setState(() => _isLoading = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Displays an input dialog allowing the user to update their contact email address.
  void _showEmailDialog() {
    final controller = TextEditingController(text: _service.config.contactEmail ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DotdigitalBrand.brightSand,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Update Profile Email', style: DotdigitalBrand.headerStyle(fontSize: 20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sets the email address on the Dotdigital push profile. This links the device to a contact in Dotdigital Marketing and populates PUSHOPTIN_xxx.',
              style: DotdigitalBrand.bodyStyle(fontSize: 13, color: DotdigitalBrand.charcoal),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Contact Email',
                hintText: 'e.g. user@example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: DotdigitalBrand.inkBlack)),
          ),
          ElevatedButton(
            onPressed: () {
              final email = controller.text.trim();
              if (email.isNotEmpty) {
                Navigator.pop(ctx);
                _handleAction(() => _service.updateUserEmail(email));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DotdigitalBrand.electricPink,
              foregroundColor: DotdigitalBrand.inkBlack,
            ),
            child: const Text('Save & Sync'),
          ),
        ],
      ),
    );
  }
}
