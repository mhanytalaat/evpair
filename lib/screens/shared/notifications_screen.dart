import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/app_notification.dart';
import '../../services/notification_service.dart';
import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../theme/ps_ev_theme.dart';
import '../admin/admin_home_screen.dart';
import '../driver/booking_status_screen.dart';
import '../driver/my_bookings_screen.dart' show MyBookingsScreen, BookingsViewMode;
import '../driver/wallet_screen.dart';

/// In-app notification center - reached by tapping the bell icon (with
/// unread-count badge) in DriverHomeScreen's top bar, or the
/// Notifications row in Profile.
///
/// FIX (9/17 update - "I need the notification to redirect to the
/// request"): notifications previously had NO `onTap` at all - tapping
/// one did nothing except show it highlighted/read. Added `_onTap`,
/// which routes to the most relevant screen based on the
/// notification's `type` (and `bookingId` where relevant):
///   - bookingRequested (host receives a new request) -> jumps straight
///     into My Bookings, "As Host" mode, Pending Approval section -
///     exactly the "redirect to the request" behavior asked for.
///   - bookingApproved / bookingDeclined / sessionStarted (driver side,
///     always carries a bookingId) -> opens that exact booking's status
///     screen.
///   - topUpApproved / topUpRejected -> opens the Wallet screen.
///   - other (covers: admin "new top-up request" / "payout ready for
///     review", and host "payout released") -> a simple keyword check
///     on the title routes an ADMIN to the matching Admin tab
///     (Top-Ups/Payouts), or a HOST to their Wallet screen for a payout
///     release notice. The generic "Test Notification" (also type
///     `other`) has no natural destination and is simply left as a
///     no-op tap, same as before.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _sendingTest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationService>().markAllRead();
    });
  }

  IconData _iconFor(NotificationType type) {
    switch (type) {
      case NotificationType.bookingRequested:
        return Icons.event_available;
      case NotificationType.bookingApproved:
        return Icons.check_circle;
      case NotificationType.bookingDeclined:
        return Icons.cancel;
      case NotificationType.topUpApproved:
        return Icons.account_balance_wallet;
      case NotificationType.topUpRejected:
        return Icons.error_outline;
      case NotificationType.sessionStarted:
        return Icons.bolt;
      case NotificationType.other:
        return Icons.notifications;
    }
  }

  Color _colorFor(NotificationType type) {
    switch (type) {
      case NotificationType.bookingRequested:
      case NotificationType.sessionStarted:
        return PsEvColors.blue;
      case NotificationType.bookingApproved:
      case NotificationType.topUpApproved:
        return PsEvColors.emerald;
      case NotificationType.bookingDeclined:
      case NotificationType.topUpRejected:
        return PsEvColors.red;
      case NotificationType.other:
        return PsEvColors.mutedText;
    }
  }

  /// NEW (9/17 update): routes a tapped notification to the most
  /// relevant screen. See class doc above for the full mapping.
  Future<void> _onTap(BuildContext context, AppNotification n) async {
    if (!n.isRead) {
      await context.read<NotificationService>().markRead(n.id);
    }
    if (!context.mounted) return;

    switch (n.type) {
      case NotificationType.bookingRequested:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const MyBookingsScreen(showPastSessions: false, initialMode: BookingsViewMode.asHost),
          ),
        );
        break;
      case NotificationType.bookingApproved:
      case NotificationType.bookingDeclined:
      case NotificationType.sessionStarted:
        if (n.bookingId != null && n.bookingId!.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: n.bookingId!)));
        }
        break;
      case NotificationType.topUpApproved:
      case NotificationType.topUpRejected:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
        break;
      case NotificationType.other:
        final title = n.title.toLowerCase();
        final isAdmin = context.read<AuthService>().isAdmin;
        if (title.contains('top-up') || title.contains('topup')) {
          if (isAdmin) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminHomeScreen(initialTab: 0)));
          }
        } else if (title.contains('payout')) {
          if (isAdmin) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminHomeScreen(initialTab: 1)));
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
          }
        }
        // "Test Notification" and any other generic `other` message has
        // no natural destination - tapping it just marks it read, same
        // as before.
        break;
    }
  }

  /// NEW (3/9 update): lets the signed-in user trigger a real push
  /// notification to their OWN device on demand, without needing to dig
  /// through the Firebase Console's "Send test message" screen (which
  /// is where the user recalled seeing a similar popup before, but
  /// couldn't find again). This writes a normal AppNotification document
  /// targeting the user's own uid - the SAME Cloud Function trigger
  /// (sendNotificationPushV2) that fires for real bookings/top-ups picks
  /// this up identically, so a successful test here is a reliable
  /// end-to-end confirmation that push delivery is fully working
  /// (device token registered, Cloud Function deployed, APNs key
  /// uploaded if on iOS, etc.) - not a separate/fake code path.
  Future<void> _sendTestNotification(BuildContext context) async {
    final uid = context.read<AppState>().currentUserId;
    if (uid == null) return;
    setState(() => _sendingTest = true);
    try {
      await context.read<NotificationService>().notify(
            recipientId: uid,
            type: NotificationType.other,
            title: 'Test Notification',
            body: 'If you can see this as a push alert (even with the app closed or your phone locked), '
                'push notifications are working correctly.',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Test notification sent. It may take a few seconds to arrive.'),
          backgroundColor: PsEvColors.emerald,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send test notification: $e'), backgroundColor: PsEvColors.red),
      );
    } finally {
      if (mounted) setState(() => _sendingTest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifications = context.watch<NotificationService>().notifications;
    final dateFmt = DateFormat('MMM d, h:mm a');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        foregroundColor: PsEvColors.slate950,
        elevation: 0,
        actions: [
          IconButton(
            icon: _sendingTest
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_outlined),
            tooltip: 'Send myself a test notification',
            onPressed: _sendingTest ? null : () => _sendTestNotification(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: PsEvColors.emeraldPale, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, size: 18, color: PsEvColors.emeraldChipText),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tap the send icon above to test push notifications on this device.',
                      style: TextStyle(fontSize: 12, color: PsEvColors.emeraldChipText),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: notifications.isEmpty
                ? const Center(child: Text('No notifications yet.', style: TextStyle(color: PsEvColors.mutedText)))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final n = notifications[index];
                      return Card(
                        color: n.isRead ? null : PsEvColors.emeraldPale,
                        child: ListTile(
                          onTap: () => _onTap(context, n),
                          leading: CircleAvatar(
                            backgroundColor: _colorFor(n.type).withOpacity(0.15),
                            child: Icon(_iconFor(n.type), color: _colorFor(n.type), size: 20),
                          ),
                          title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.body, style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(dateFmt.format(n.createdAt), style: const TextStyle(fontSize: 10, color: PsEvColors.mutedText)),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right, color: PsEvColors.mutedText),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
