import 'package:flutter/material.dart';
import 'package:dotdigital_push/dotdigital_push.dart';
import 'services/notification_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/promo_screen.dart';
import 'theme/dotdigital_brand.dart';
import 'widgets/in_app_toast.dart';

// ============================================================================
// DOTDIGITAL MOBILE PUSH EXAMPLE APPLICATION
// ============================================================================
// This application demonstrates best practice integration with Dotdigital's
// Mobile Push Channel using the Comapi Foundation native SDKs.
//
// HIGH LEVEL NARRATIVE & EVENT FLOW:
// 1. App Launch: NotificationService initializes, restores persisted configs
//    from local storage, and wires event streams for foreground pushes, notification
//    taps, and silent background data.
// 2. Cold Start Taps: If the app was launched by tapping a push while closed,
//    `getInitialNotification()` retrieves the launch intent/response and navigates
//    to the targeted screen (e.g. `ddexample://product/123`).
// 3. Foreground Notifications: An `InAppToastOverlay` wraps the app tree to
//    render an animated top toast when a message arrives while the user is inside
//    the app, since mobile operating systems suppress system-tray alerts in foreground.
// 4. Deep Link Routing: Custom scheme `ddexample:` routes seamlessly to
//    dedicated destination screens (Product Detail, Promo Screen, etc.).
//
// ⚠️ SECURITY WARNING:
// Storing Shared Secrets in mobile application packages is UNSAFE in production.
// This example app supports client-side JWT generation solely for demonstration,
// sandbox evaluation, and documentation validation. In production environments,
// JWTs must be requested from an authenticated server-side API.
// ============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize service & restore settings from storage
  final notificationService = NotificationService();
  await notificationService.init();

  runApp(const DotdigitalExampleApp());
}

class DotdigitalExampleApp extends StatefulWidget {
  const DotdigitalExampleApp({super.key});

  @override
  State<DotdigitalExampleApp> createState() => _DotdigitalExampleAppState();
}

class _DotdigitalExampleAppState extends State<DotdigitalExampleApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Listen to deep links forwarded from native SDK tap handler or in-app triggers
    _notificationService.onNavigateDeepLink.listen((event) {
      _handleDeepLink(
        event.url,
        extraData: event.extraData,
        rawPayload: event.rawPayload,
      );
    });

    // Check if app was cold launched from a notification tap
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _notificationService.startLifecycle();
      try {
        final initialTap = await DotdigitalPush.getInitialNotification();
        if (initialTap != null) {
          final resolvedUrl = NotificationService.extractUrlFromPayload(
            directUrl: initialTap.url,
            customData: initialTap.customData,
            rawPayload: initialTap.rawPayload,
          );
          if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
            _handleDeepLink(
              resolvedUrl,
              extraData: initialTap.customData,
              rawPayload: initialTap.rawPayload,
            );
          }
        }
      } catch (_) {}
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _notificationService.startLifecycle();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Parses incoming deep link URLs and routes to the matching destination screen
  /// or opens web URLs (`http` / `https`) in the device browser.
  ///
  /// Supported routes:
  /// - `http://` or `https://` -> Opens external browser & triggers Dotdigital click tracking
  /// - `ddexample://product/:id` -> [ProductDetailScreen]
  /// - `ddexample://promo` -> [PromoScreen]
  /// - Any other URL -> Launches via OS or displays alert fallback.
  Future<void> _handleDeepLink(
    String urlString, {
    Map<String, dynamic>? extraData,
    Map<String, dynamic>? rawPayload,
  }) async {
    final trimmed = urlString.trim();
    if (trimmed.isEmpty) return;

    final normalizedUrl = (!trimmed.contains('://') &&
            (trimmed.toLowerCase().startsWith('www.') || trimmed.contains('.')))
        ? 'https://$trimmed'
        : trimmed;

    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null) return;

    final scheme = uri.scheme.toLowerCase();

    // 1. Web URLs (e.g. "Open deep link" with web address, or "Open a survey, page, or form")
    if (scheme == 'http' || scheme == 'https') {
      await DotdigitalPush.openDeepLink(
        url: normalizedUrl,
        rawPayload: rawPayload,
        launchExternal: true,
      );
      return;
    }

    // 2. Custom App Scheme ("ddexample://")
    if (scheme == 'ddexample') {
      // Trigger Dotdigital click tracking in the background if rawPayload contains dd_deepLink
      if (rawPayload != null && rawPayload.isNotEmpty) {
        DotdigitalPush.openDeepLink(
          url: normalizedUrl,
          rawPayload: rawPayload,
          launchExternal: false,
        );
      }

      final host = uri.host;
      final pathSegments = uri.pathSegments;

      if (host == 'product' || (pathSegments.isNotEmpty && pathSegments.first == 'product')) {
        final productId = host == 'product' && pathSegments.isNotEmpty
            ? pathSegments.first
            : (pathSegments.length > 1 ? pathSegments[1] : '1');

        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(
              productId: productId,
              extraData: extraData,
            ),
          ),
        );
      } else if (host == 'promo' || (pathSegments.isNotEmpty && pathSegments.first == 'promo')) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => PromoScreen(extraData: extraData),
          ),
        );
      } else {
        // Generic deep link destination
        _showUnknownDeepLinkDialog(normalizedUrl, rawPayload: rawPayload);
      }
    } else {
      // Attempt to launch external URI scheme automatically via the OS first
      final launched = await DotdigitalPush.openDeepLink(
        url: normalizedUrl,
        rawPayload: rawPayload,
        launchExternal: true,
      );
      if (!launched) {
        _showUnknownDeepLinkDialog(normalizedUrl, rawPayload: rawPayload);
      }
    }
  }

  /// Displays an informational dialog when an unrecognized deep link is received.
  void _showUnknownDeepLinkDialog(String url, {Map<String, dynamic>? rawPayload}) {
    final context = _navigatorKey.currentContext;
    if (context != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Deep Link Received'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The following URL was dispatched to the app:'),
              const SizedBox(height: 8),
              SelectableText(
                url,
                style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                DotdigitalPush.openDeepLink(
                  url: url,
                  rawPayload: rawPayload,
                  launchExternal: true,
                );
              },
              child: const Text('Open in Browser / OS'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Dotdigital Push Example',
      debugShowCheckedModeBanner: false,
      theme: DotdigitalBrand.buildTheme(),
      builder: (context, child) {
        return InAppToastOverlay(
          toastStream: _notificationService.onShowToast,
          onDeepLinkTap: (link, {extraData, rawPayload}) =>
              _handleDeepLink(link, extraData: extraData, rawPayload: rawPayload),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: DashboardScreen(
        onDeepLinkTap: (link, {extraData, rawPayload}) =>
            _handleDeepLink(link, extraData: extraData, rawPayload: rawPayload),
      ),
    );
  }
}
