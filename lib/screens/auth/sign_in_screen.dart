import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/booking_service.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/wallet_service.dart';
import '../../state/app_state.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import 'register_screen.dart';

/// Lets a previously-registered user sign back in with email + password
/// via Firebase Authentication.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
      if (!mounted) return;
      final auth = context.read<AuthService>();
      final uid = auth.uid;
      if (uid != null) {
        await context.read<AppState>().setCurrentUserAndHydrate(uid);
        if (!mounted) return;
        context.read<BookingService>().hydrate(uid);
        context.read<NotificationService>().listenFor(uid);
        await PushNotificationService.initAndRegister(uid);
        // FIX (3/9 update): sign-in is also where the admin's live,
        // all-top-ups listener must be attached - previously this was
        // only ever set up in main.dart on a fresh cold app start, so
        // signing in fresh via this screen (without restarting the app)
        // never gave the admin visibility into other drivers' pending
        // top-ups either.
        final wallet = context.read<WalletService>();
        await wallet.hydrateFromFirestore(uid);
        if (auth.isAdmin) {
          wallet.listenToAllTopUpRequestsForAdmin();
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = AuthService.messageForAuthError(e));
    } catch (e) {
      setState(() => _error = 'Sign in failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goToRegister() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
    if (result == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PsEvAppBar(title: 'Sign In', showProfileAction: false),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Sign in with your email and password to access your cars, chargers, wallet and bookings.',
                  style: TextStyle(color: PsEvColors.mutedText, fontSize: 13),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Email', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                      ),
                      const SizedBox(height: 12),
                      const Text('Password', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!, style: const TextStyle(color: PsEvColors.red, fontSize: 12)),
                      ],
                      const SizedBox(height: 16),
                      PsEvFilledButton(
                        label: _loading ? 'Checking...' : 'Sign In',
                        icon: Icons.login,
                        onTap: _loading ? null : _submit,
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: _loading ? null : _goToRegister,
                          child: const Text("Don't have an account? Register"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
