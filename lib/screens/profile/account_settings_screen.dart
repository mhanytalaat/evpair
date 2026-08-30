import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../state/country_codes.dart';
import '../../utils/phone_number_validator.dart';
import '../../theme/ps_ev_theme.dart';

/// Account details form, moved out of ProfileScreen's body so that
/// "Account Settings" can be a tappable row in the Manage list, exactly
/// like My Cars / My Stations / Wallet & Top-Up / Booking History.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});
  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;
  String? _error;
  String _countryCode = '+20';

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    _firstNameCtrl = TextEditingController(text: auth.firstName ?? '');
    _lastNameCtrl = TextEditingController(text: auth.lastName ?? '');
    final storedPhone = auth.phone ?? '';
    final matched = kCountryDialCodes
        .where((c) => storedPhone.startsWith(c.code))
        .fold<CountryDialCode?>(null, (best, c) {
      if (best == null || c.code.length > best.code.length) return c;
      return best;
    });
    if (matched != null) {
      _countryCode = matched.code;
      final remainder = storedPhone.substring(matched.code.length);
      // Item #1: numbers are now STORED without the redundant leading 0
      // (see PhoneNumberValidator.toE164), so it's added back here only
      // for display/editing, matching the "01xxxxxxxxx" typing
      // convention users are used to.
      final display = matched.code == '+20' ? PhoneNumberValidator.addLeadingZeroIfMissing(remainder) : remainder;
      _phoneCtrl = TextEditingController(text: display);
    } else {
      _phoneCtrl = TextEditingController(text: storedPhone);
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    // Item #1: strip the redundant leading 0 before combining with the
    // country code for storage (see PhoneNumberValidator.toE164).
    final normalizedPhone = PhoneNumberValidator.toE164(_phoneCtrl.text, countryCode: _countryCode);
    // Item #6: reject duplicate phone numbers here too, excluding the
    // signed-in user's own existing record.
    final phoneTaken = await auth.isPhoneNumberTaken(normalizedPhone, excludeUid: auth.uid);
    if (phoneTaken) {
      setState(() {
        _saving = false;
        _error = 'This phone number is already used by another account.';
      });
      return;
    }
    await auth.updateProfile(
      firstName: _firstNameCtrl.text,
      lastName: _lastNameCtrl.text,
      phone: normalizedPhone,
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
        title: const Text('Account Settings'),
        backgroundColor: Colors.white,
        foregroundColor: PsEvColors.slate950,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                            validator: (v) => PhoneNumberValidator.validate(v, countryCode: _countryCode),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: PsEvColors.red, fontSize: 12)),
                    ],
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
        ],
      ),
    );
  }
}
