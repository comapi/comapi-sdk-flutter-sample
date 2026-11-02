import 'package:flutter/material.dart';
import '../models/notification_history_item.dart';
import '../theme/dotdigital_brand.dart';

// ============================================================================
// IN-APP TOAST NOTIFICATION OVERLAY
// ============================================================================
// HIGH LEVEL NARRATIVE:
// On both Android and iOS, the operating system suppresses system-tray push
// notifications when an application is active in the foreground.
//
// As documented in Dotdigital's SDK guide:
// "To display a push message while your app is in the foreground, you must do it yourself."
//
// This widget wraps the root Flutter widget tree and listens to `toastStream`.
// When a foreground push arrives, it slides an animated toast banner down from
// the top of the screen displaying the notification title, body, and action buttons.
//
// - Tapping "Open" navigates directly to the deep link (`ddexample://...`).
// - Tapping "Close" or waiting 5 seconds dismisses the toast.
// - All messages are simultaneously preserved in the Notification Inbox for later review.
// ============================================================================

class InAppToastOverlay extends StatefulWidget {
  final Widget child;
  final Stream<NotificationHistoryItem> toastStream;
  final void Function(
    String deepLinkUrl, {
    Map<String, dynamic>? extraData,
    Map<String, dynamic>? rawPayload,
  })? onDeepLinkTap;

  const InAppToastOverlay({
    super.key,
    required this.child,
    required this.toastStream,
    this.onDeepLinkTap,
  });

  @override
  State<InAppToastOverlay> createState() => _InAppToastOverlayState();
}

class _InAppToastOverlayState extends State<InAppToastOverlay> with SingleTickerProviderStateMixin {
  NotificationHistoryItem? _currentItem;
  late AnimationController _animController;
  late Animation<Offset> _offsetAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _offsetAnim = Tween<Offset>(
      begin: const Offset(0.0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutBack));

    widget.toastStream.listen((item) {
      _showToast(item);
    });
  }

  /// Displays an incoming notification item as an animated top toast banner.
  void _showToast(NotificationHistoryItem item) {
    setState(() {
      _currentItem = item;
    });
    _animController.forward(from: 0.0);

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _currentItem?.id == item.id) {
        _dismissToast();
      }
    });
  }

  /// Dismisses the toast banner by animating it off the screen.
  void _dismissToast() {
    _animController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _currentItem = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_currentItem != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: SlideTransition(
                position: _offsetAnim,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Material(
                    elevation: 10,
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: (_currentItem!.deepLinkUrl != null &&
                              _currentItem!.deepLinkUrl!.isNotEmpty)
                          ? () {
                              final item = _currentItem!;
                              final link = item.deepLinkUrl!;
                              _dismissToast();
                              widget.onDeepLinkTap?.call(
                                link,
                                extraData: item.customData,
                                rawPayload: item.rawPayload,
                              );
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: DotdigitalBrand.inkBlack,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: DotdigitalBrand.electricPink, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: const BoxDecoration(
                                    color: DotdigitalBrand.electricPink,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.notifications_active,
                                    color: DotdigitalBrand.inkBlack,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'FOREGROUND PUSH',
                                        style: DotdigitalBrand.eyebrowStyle(
                                          fontSize: 9,
                                          color: DotdigitalBrand.signalPink,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _currentItem!.title.isNotEmpty
                                            ? _currentItem!.title
                                            : 'Dotdigital Notification',
                                        style: DotdigitalBrand.headerStyle(
                                          fontSize: 16,
                                          color: DotdigitalBrand.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                                  onPressed: _dismissToast,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                            if (_currentItem!.body.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                _currentItem!.body,
                                style: DotdigitalBrand.bodyStyle(
                                  fontSize: 13,
                                  color: DotdigitalBrand.white,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (_currentItem!.deepLinkUrl != null &&
                                _currentItem!.deepLinkUrl!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.link, color: DotdigitalBrand.signalPink, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _currentItem!.deepLinkUrl!,
                                      style: const TextStyle(
                                        color: DotdigitalBrand.signalPink,
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () {
                                      final item = _currentItem!;
                                      final link = item.deepLinkUrl!;
                                      _dismissToast();
                                      widget.onDeepLinkTap?.call(
                                        link,
                                        extraData: item.customData,
                                        rawPayload: item.rawPayload,
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: DotdigitalBrand.neon,
                                      foregroundColor: DotdigitalBrand.inkBlack,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: const StadiumBorder(),
                                    ),
                                    child: Text(
                                      'Open',
                                      style: TextStyle(
                                        fontFamily: DotdigitalBrand.fontBody,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
