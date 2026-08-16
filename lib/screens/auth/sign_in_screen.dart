import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import 'register_screen.dart';

/// Lets a previously-registered user sign back in using the email they
/// registered with. If no matching Firestore profile is found, offers to
/// take them to Register instead.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final ok = await context.read<AuthService>().signIn(_emailCtrl.text.trim());

    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'No account found with this email. Please register instead.');
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
      appBar: const PsEvAppBar(title: 'Sign In'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Enter the email you used to register to access your cars, chargers, wallet and bookings.',
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
