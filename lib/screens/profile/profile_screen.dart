import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../theme/ps_ev_theme.dart';
import '../root/app_root.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    _firstNameCtrl = TextEditingController(text: auth.firstName ?? '');
    _lastNameCtrl = TextEditingController(text: auth.lastName ?? '');
    _phoneCtrl = TextEditingController(text: auth.phone ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
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
    if (!mounted) return;
    await context.read<AppState>().clearCurrentUserAndData();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppRoot()),
      (route) => false,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    await context.read<AuthService>().updateProfile(
          firstName: _firstNameCtrl.text,
          lastName: _lastNameCtrl.text,
          phone: _phoneCtrl.text,
        );

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved to Firestore')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('First name', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _firstNameCtrl,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your first name' : null,
                    ),
                    const SizedBox(height: 12),
                    const Text('Last name', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _lastNameCtrl,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your last name' : null,
                    ),
                    const SizedBox(height: 12),
                    const Text('Email', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                    const SizedBox(height: 4),
                    TextFormField(
                      initialValue: auth.email ?? '',
                      enabled: false,
                      decoration: const InputDecoration(
                        helperText: 'Email is tied to your sign-in and cannot be changed here.',
                        helperMaxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Phone number', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your phone number' : null,
                    ),
                    const SizedBox(height: 16),
                    PsEvFilledButton(
                      label: _saving ? 'Saving...' : 'Save Profile',
                      icon: Icons.cloud_done_outlined,
                      onTap: _saving ? null : _save,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (auth.isRegistered) ...[
            const SizedBox(height: 12),
            PsEvFilledButton(
              label: 'Sign Out',
              icon: Icons.logout,
              color: PsEvColors.red,
              onTap: _signOut,
            ),
          ],
        ],
      ),
    );
  }
}
