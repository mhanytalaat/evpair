import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/support_settings_service.dart';
import '../../theme/ps_ev_theme.dart';

/// Shows EVPair's support email/phone/WhatsApp, read live from
/// `appSettings/support` in Firestore (see SupportSettingsService) - so
/// updating any of these values in the Firebase console updates what
/// every user sees instantly, no app release needed.
class ContactSupportScreen extends StatelessWidget {
  const ContactSupportScreen({super.key});

  Future<void> _openEmail(BuildContext context, String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open an email app.')));
    }
  }

  Future<void> _openPhone(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the phone dialer.')));
    }
  }

  Future<void> _openWhatsApp(BuildContext context, String whatsapp) async {
    final digits = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Support'),
        backgroundColor: Colors.white,
        foregroundColor: PsEvColors.slate950,
        elevation: 0,
      ),
      body: StreamBuilder<SupportSettings>(
        stream: SupportSettingsService.watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = snapshot.data!;
          if (!s.hasAnyContact) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Support contact details have not been set up yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PsEvColors.mutedText),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (s.email?.trim().isNotEmpty ?? false)
                _row(
                  icon: Icons.email_outlined,
                  color: PsEvColors.blue,
                  title: 'Email',
                  subtitle: s.email!,
                  onTap: () => _openEmail(context, s.email!),
                ),
              if (s.phone?.trim().isNotEmpty ?? false)
                _row(
                  icon: Icons.call_outlined,
                  color: PsEvColors.emerald,
                  title: 'Phone',
                  subtitle: s.phone!,
                  onTap: () => _openPhone(context, s.phone!),
                ),
              if (s.whatsapp?.trim().isNotEmpty ?? false)
                _row(
                  icon: Icons.chat_outlined,
                  color: PsEvColors.emerald,
                  title: 'WhatsApp',
                  subtitle: s.whatsapp!,
                  onTap: () => _openWhatsApp(context, s.whatsapp!),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: PsEvColors.mutedText),
        onTap: onTap,
      ),
    );
  }
}
