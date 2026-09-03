import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/app_notification.dart';
import '../../services/notification_service.dart';
import '../../theme/ps_ev_theme.dart';

/// In-app notification center - the list itself (separate from the
/// actual push notification that may also arrive on the device, see
/// PushNotificationService + functions/index.js). Reached by tapping the
/// bell icon (with unread-count badge) in DriverHomeScreen's top bar.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Mark everything read as soon as the user opens this screen - the
    // badge count on the home screen will drop to 0 immediately since
    // NotificationService is a live ChangeNotifier.
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
      ),
      body: notifications.isEmpty
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
                  ),
                );
              },
            ),
    );
  }
}
