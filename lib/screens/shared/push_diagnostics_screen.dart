import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/push_notification_service.dart';
import '../../state/app_state.dart';
import '../../theme/ps_ev_theme.dart';

/// Shows the live `pushDebug` diagnostic record written by
/// PushNotificationService directly in the app - no Firestore Console,
/// Mac, Xcode, or terminal access needed to see exactly why push
/// notifications aren't registering on this device. Reached from
/// Profile -> "Push Notification Diagnostics" (added below
/// notifications row).
class PushDiagnosticsScreen extends StatelessWidget {
  const PushDiagnosticsScreen({super.key});

  Color _statusColor(String? permissionStatus, bool? tokenSaved, String? lastError) {
    if (lastError != null && lastError.isNotEmpty) return PsEvColors.red;
    if (permissionStatus == 'authorized' && tokenSaved == true) return PsEvColors.emerald;
    if (permissionStatus == 'denied') return PsEvColors.red;
    return PsEvColors.amber;
  }

  String _summaryFor(String? permissionStatus, bool? tokenObtained, bool? tokenSaved, String? lastError) {
    if (permissionStatus == null) return 'No registration attempt recorded yet on this device.';
    if (permissionStatus == 'denied') return 'Notification permission was DENIED. Enable it in your phone\'s Settings app, then reopen EVPair.';
    if (tokenObtained == false) return 'Permission was granted, but the device could not obtain a push token yet. This can happen right after granting permission on iOS - reopening the app usually fixes it automatically.';
    if (tokenSaved == true) return '✅ Push notifications are fully registered on this device.';
    if (lastError != null && lastError.isNotEmpty) return 'An error occurred during registration (see details below).';
    return 'Registration is incomplete - see details below.';
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AppState>().currentUserId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Notification Diagnostics'),
        backgroundColor: Colors.white,
        foregroundColor: PsEvColors.slate950,
        elevation: 0,
      ),
      body: uid == null
          ? const Center(child: Text('Please sign in first.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data();
                final debug = data?['pushDebug'] as Map<String, dynamic>?;
                final tokens = (data?['fcmTokens'] as List?)?.cast<String>() ?? const [];
                final permissionStatus = debug?['permissionStatus'] as String?;
                final tokenObtained = debug?['tokenObtained'] as bool?;
                final tokenSaved = debug?['tokenSaved'] as bool?;
                final lastError = debug?['lastError'] as String?;
                final platform = debug?['platform'] as String?;
                final lastAttempt = debug?['lastAttemptAt'];
                final lastAttemptStr = lastAttempt is Timestamp
                    ? DateFormat('MMM d, h:mm:ss a').format(lastAttempt.toDate())
                    : 'Never';
                final color = _statusColor(permissionStatus, tokenSaved, lastError);
                final summary = _summaryFor(permissionStatus, tokenObtained, tokenSaved, lastError);

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      color: color.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  color == PsEvColors.emerald
                                      ? Icons.check_circle
                                      : (color == PsEvColors.red ? Icons.error : Icons.warning_amber_rounded),
                                  color: color,
                                ),
                                const SizedBox(width: 8),
                                const Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(summary, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          _detailRow('Platform', platform ?? '—'),
                          const Divider(height: 1),
                          _detailRow('Last attempt', lastAttemptStr),
                          const Divider(height: 1),
                          _detailRow('Permission status', permissionStatus ?? '—'),
                          const Divider(height: 1),
                          _detailRow('Token obtained', tokenObtained == null ? '—' : (tokenObtained ? 'Yes' : 'No')),
                          const Divider(height: 1),
                          _detailRow('Token saved to Firestore', tokenSaved == null ? '—' : (tokenSaved ? 'Yes' : 'No')),
                          const Divider(height: 1),
                          _detailRow('Registered device tokens', '${tokens.length}'),
                        ],
                      ),
                    ),
                    if (lastError != null && lastError.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Last Error', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: PsEvColors.redChip, borderRadius: BorderRadius.circular(12)),
                        child: Text(lastError, style: const TextStyle(color: PsEvColors.redChipText, fontSize: 12)),
                      ),
                    ],
                    const SizedBox(height: 20),
                    PsEvFilledButton(
                      icon: Icons.refresh,
                      label: 'Retry Registration Now',
                      onTap: () async {
                        await PushNotificationService.initAndRegister(uid);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Retried - status above will update automatically.')),
                          );
                        }
                      },
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: PsEvColors.mutedText)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
