import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PsEvAppBar(title: 'Create Your Account'),
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
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your phone number' : null,
                      ),
                      const SizedBox(height: 16),
                      PsEvFilledButton(
                        label: 'Register & Continue',
                      onTap: () async {
                        if (!_formKey.currentState!.validate()) return;
                        await context.read<AuthService>().register(
                              firstName: _firstNameCtrl.text.trim(),
                              lastName: _lastNameCtrl.text.trim(),
                              email: _emailCtrl.text.trim(),
                              phone: _phoneCtrl.text.trim(),
                            );
                        if (!context.mounted) return;
                        Navigator.pop(context, true);
                      },


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

Future<bool> ensureRegistered(BuildContext context) async {
  final auth = context.read<AuthService>();
  if (auth.isRegistered) return true;
  final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
  return result == true;
}
