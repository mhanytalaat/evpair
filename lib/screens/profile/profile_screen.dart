import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/partner_service.dart';
import '../../services/profile_photo_service.dart';
import '../../state/app_state.dart';
import '../../theme/ps_ev_theme.dart';
import '../auth/register_screen.dart';
import '../driver/my_cars_screen.dart';
import '../driver/wallet_screen.dart';
import '../driver/my_bookings_screen.dart';
import '../host/host_home_screen.dart';
import '../root/app_root.dart';
import '../legal/legal_document_screen.dart';
import '../partner/home_installation_screen.dart';
import '../partner/partner_jobs_screen.dart';
import '../shared/contact_support_screen.dart';
import 'account_settings_screen.dart';

/// Profile / account hub. Cars, Stations, Wallet, Booking History, and
/// Home Installation & Equipment are surfaced here as "Manage" rows
/// since they're occasional-use actions, not everyday destinations that
/// deserve footer space. Account Settings, Legal, and Contact Support
/// are listed the same way for a single consistent list-row pattern.
///
/// The avatar at the top is now tappable - lets the user set/change/
/// remove their own profile photo (see ProfilePhotoService), stored as
/// base64 in Firestore so it works identically on web, iOS, and Android
/// with no Storage/CORS setup required.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of your EVPair account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed != true) return;

    await context.read<AuthService>().signOut();
    if (!context.mounted) return;
    await context.read<AppState>().clearCurrentUserAndData();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppRoot()),
      (route) => false,
    );
  }

  Future<void> _showChangePhotoSheet(BuildContext context, String uid) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: PsEvColors.red),
              title: const Text('Remove Photo', style: TextStyle(color: PsEvColors.red)),
              onTap: () => Navigator.pop(sheetContext, 'remove'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    if (choice == 'remove') {
      await ProfilePhotoService.removePhoto(uid);
      return;
    }

    final source = choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
    try {
      await ProfilePhotoService.pickAndSave(uid, source: source);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update your photo: $e'), backgroundColor: PsEvColors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final app = context.watch<AppState>();
    final partnerService = context.watch<PartnerService>();
    final uid = app.currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: Colors.white,
        foregroundColor: PsEvColors.slate950,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: uid == null ? null : () => _showChangePhotoSheet(context, uid),
                    child: Stack(
                      children: [
                        uid == null
                            ? _avatarInitialsOnly(auth)
                            : StreamBuilder<Uint8List?>(
                                stream: ProfilePhotoService.watch(uid),
                                builder: (context, snapshot) {
                                  final bytes = snapshot.data;
                                  return CircleAvatar(
                                    radius: 38,
                                    backgroundColor: PsEvColors.emerald,
                                    backgroundImage: bytes != null ? MemoryImage(bytes) : null,
                                    child: bytes == null
                                        ? Text(
                                            auth.initials,
                                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                                          )
                                        : null,
                                  );
                                },
                              ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: PsEvColors.emerald,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    auth.displayName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  if ((auth.email ?? '').isNotEmpty)
                    Text(
                      auth.email!,
                      style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText),
                    ),
                  if (partnerService.isPartner)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: PsEvTag(label: 'Installation Partner'),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Manage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
          ),
          Card(
            child: Column(
              children: [
                _ProfileRow(
                  icon: Icons.electric_car,
                  iconColor: PsEvColors.emerald,
                  title: 'My Cars',
                  subtitle: 'Add or manage your vehicles',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCarsScreen())),
                ),
                const Divider(height: 1),
                _ProfileRow(
                  icon: Icons.ev_station,
                  iconColor: PsEvColors.blue,
                  title: 'My Stations',
                  subtitle: 'Host or manage your charging stations',
                  onTap: () async {
                    final ok = await ensureRegistered(context);
                    if (!ok || !context.mounted) return;
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HostHomeScreen()));
                  },
                ),
                const Divider(height: 1),
                _ProfileRow(
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: PsEvColors.amber,
                  title: 'Wallet & Top-Up',
                  subtitle: 'Balance, transactions, and top-up',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                ),
                const Divider(height: 1),
                _ProfileRow(
                  icon: Icons.list_alt,
                  iconColor: PsEvColors.slateText,
                  title: 'Booking History',
                  subtitle: 'Your past and ongoing bookings',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookingsScreen())),
                ),
                const Divider(height: 1),
                _ProfileRow(
                  icon: Icons.home_work_outlined,
                  iconColor: PsEvColors.blue,
                  title: 'Home Installation & Equipment',
                  subtitle: 'Check equipment, or request a home service',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeInstallationScreen())),
                  isLast: true,
                ),
              ],
            ),
          ),

          if (partnerService.isPartner) ...[
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Partner Tools', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
            ),
            Card(
              child: _ProfileRow(
                icon: Icons.build_circle_outlined,
                iconColor: PsEvColors.emerald,
                title: 'Partner Jobs',
                subtitle: 'Accept open service requests and manage your jobs',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartnerJobsScreen())),
                isLast: true,
              ),
            ),
          ],

          const SizedBox(height: 12),

          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
          ),
          Card(
            child: Column(
              children: [
                _ProfileRow(
                  icon: Icons.person_outline,
                  iconColor: PsEvColors.slateText,
                  title: 'Account Settings',
                  subtitle: 'Name, email, and phone number',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountSettingsScreen())),
                ),
                const Divider(height: 1),
                _ProfileRow(
                  icon: Icons.support_agent_outlined,
                  iconColor: PsEvColors.emerald,
                  title: 'Contact Support',
                  subtitle: 'Email, phone, and WhatsApp',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactSupportScreen())),
                ),
                const Divider(height: 1),
                _ProfileRow(
                  icon: Icons.description_outlined,
                  iconColor: PsEvColors.slateText,
                  title: 'Terms & Conditions',
                  subtitle: 'Review the latest terms of service',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(documentId: 'termsAndConditions', title: 'Terms & Conditions'),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _ProfileRow(
                  icon: Icons.privacy_tip_outlined,
                  iconColor: PsEvColors.slateText,
                  title: 'Privacy Policy',
                  subtitle: 'How your data is collected and used',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(documentId: 'privacyPolicy', title: 'Privacy Policy'),
                    ),
                  ),
                  isLast: true,
                ),
              ],
            ),
          ),

          if (auth.isRegistered) ...[
            const SizedBox(height: 16),
            PsEvFilledButton(
              label: 'Sign Out',
              icon: Icons.logout,
              color: PsEvColors.red,
              onTap: () => _signOut(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatarInitialsOnly(AuthService auth) {
    return CircleAvatar(
      radius: 38,
      backgroundColor: PsEvColors.emerald,
      child: Text(
        auth.initials,
        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLast;

  const _ProfileRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        bottom: isLast ? const Radius.circular(PsEvRadii.card) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: iconColor.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: PsEvColors.mutedText),
          ],
        ),
      ),
    );
  }
}
