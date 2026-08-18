import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import '../../state/app_state.dart';
import '../../state/country_codes.dart';
import 'sign_in_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;
  bool _obscurePassword = true;

  // Country dial code for the phone number, defaulting to Egypt. Israel is
  // intentionally excluded from kCountryDialCodes.
  String _countryCode = '+20';

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().register(
            firstName: _firstNameCtrl.text.trim(),
            lastName: _lastNameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            phone: '$_countryCode${_phoneCtrl.text.trim()}',
            password: _passwordCtrl.text,
          );
      if (!mounted) return;
      final uid = context.read<AuthService>().uid;
      if (uid != null) {
        await context.read<AppState>().setCurrentUserAndHydrate(uid);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = AuthService.messageForAuthError(e));
    } catch (e) {
      setState(() => _error = 'Registration failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PsEvAppBar(title: 'Create Your Account', showProfileAction: false),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Please register to book a charging station or add your own charger.',
                  style: TextStyle(color: PsEvColors.mutedText, fontSize: 13),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
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
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                      ),
                      const SizedBox(height: 12),
                      const Text('Phone number', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: PsEvColors.slate200, width: 1.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _countryCode,
                                items: kCountryDialCodes
                                    .map((c) => DropdownMenuItem(
                                          value: c.code,
                                          child: Text(c.code, style: const TextStyle(fontSize: 13)),
                                        ))
                                    .toList(),
                                onChanged: (v) => setState(() => _countryCode = v!),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              maxLength: 11,
                              decoration: const InputDecoration(counterText: '', hintText: '01xxxxxxxxx'),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Enter your mobile number';
                                if (!RegExp(r'^\d{11}$').hasMatch(v.trim())) return 'Must be exactly 11 digits';
                                return null;
                              },
                            ),
                          ),
                        ],
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
                        validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                      ),
                      const SizedBox(height: 12),
                      const Text('Confirm password', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _confirmPasswordCtrl,
                        obscureText: _obscurePassword,
                        validator: (v) => (v != _passwordCtrl.text) ? 'Passwords do not match' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: PsEvColors.red, fontSize: 12)),
                      ],
                      const SizedBox(height: 16),
                      PsEvFilledButton(
                        label: _submitting ? 'Creating account...' : 'Register & Continue',
                        onTap: _submitting ? null : _submit,
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: _submitting
                              ? null
                              : () async {
                                  final result = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(builder: (_) => const SignInScreen()),
                                  );
                                  if (result == true && context.mounted) Navigator.pop(context, true);
                                },
                          child: const Text('Already have an account? Sign In'),
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

/// Ensures the user is authenticated before proceeding with an action that
/// requires an account (adding a car, adding a charger, booking, etc.).
/// If the user is a guest, presents a choice between Sign In (existing
/// account) and Register (new account) before allowing the action.
Future<bool> ensureRegistered(BuildContext context) async {
  final auth = context.read<AuthService>();
  if (auth.isRegistered) return true;
  final choice = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Please sign in or register to continue',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.login, color: PsEvColors.emerald),
              title: const Text('Sign In'),
              subtitle: const Text('I already have an account'),
              onTap: () => Navigator.pop(ctx, 'signin'),
            ),
            ListTile(
              leading: const Icon(Icons.person_add, color: PsEvColors.emerald),
              title: const Text('Register'),
              subtitle: const Text('Create a new account'),
              onTap: () => Navigator.pop(ctx, 'register'),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;
  if (choice == 'signin') {
    final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SignInScreen()));
    return result == true;
  }
  final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
  return result == true;
}
