import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/partner_service.dart';
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
import 'account_settings_screen.dart';

/// Profile / account hub. Cars, Stations, Wallet, and Booking History
/// are surfaced here as "Manage" rows since they're occasional-use
/// actions, not everyday destinations that deserve footer space.
/// Account Settings and Legal are listed the same way for a single
/// consistent list-row pattern throughout this screen - nothing is
/// shown as an inline form directly on this page anymore.
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final partnerService = context.watch<PartnerService>();
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
                  CircleAvatar(
                    radius: 38,
                    backgroundColor: PsEvColors.emerald,
                    child: Text(
                      auth.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
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
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
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
                  subtitle: 'Request a home install, or borrow/buy cables & adaptors',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeInstallationScreen())),
                  isLast: true,
                ),
              ],
            ),
          ),

          // -----------------------------------------------------------
          // Partner Jobs - only shown to signed-in users who are
          // registered installation partners (a doc exists at
          // installPartners/{uid}). Everyone else never sees this row.
          // -----------------------------------------------------------
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
                subtitle: 'Accept open installation requests and manage your jobs',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartnerJobsScreen())),
                isLast: true,
              ),
            ),
          ],

          const SizedBox(height: 12),

          // -----------------------------------------------------------
          // Account Settings now lives as a row here, same pattern as
          // every item above, instead of an inline form directly on
          // this page.
          // -----------------------------------------------------------
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
