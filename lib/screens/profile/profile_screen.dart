import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../state/country_codes.dart';
import '../../theme/ps_ev_theme.dart';
import '../auth/register_screen.dart';
import '../driver/my_cars_screen.dart';
import '../driver/wallet_screen.dart';
import '../driver/my_bookings_screen.dart';
import '../host/host_home_screen.dart';
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

  // Country dial code for the phone number. If the stored phone already
  // starts with a known dial code, split it off so the dropdown and the
  // digits field show correctly; otherwise default to Egypt.
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
      _phoneCtrl = TextEditingController(text: storedPhone.substring(matched.code.length));
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
          phone: '$_countryCode${_phoneCtrl.text.trim()}',
        );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved to Firestore')),
    );
  }

  Future<void> _openStations() async {
    final ok = await ensureRegistered(context);
    if (!ok || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const HostHomeScreen()));
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

          // -----------------------------------------------------------
          // Manage section: Cars and Stations now live here instead of
          // the home-screen footer, since they're setup-once actions
          // rather than everyday destinations. Wallet & Top-Up and
          // Booking History are also listed here for a single place to
          // find every account-related action, even though Wallet and
          // Sessions/Bookings also have quick-access icons on the home
          // screen's floating footer.
          // -----------------------------------------------------------
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Manage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
          ),
          Card(
            child: Column(
              children: [
                _manageRow(
                  icon: Icons.electric_car,
                  iconColor: PsEvColors.emerald,
                  title: 'My Cars',
                  subtitle: 'Add or manage your vehicles',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCarsScreen())),
                ),
                const Divider(height: 1),
                _manageRow(
                  icon: Icons.ev_station,
                  iconColor: PsEvColors.blue,
                  title: 'My Stations',
                  subtitle: 'Host or manage your charging stations',
                  onTap: _openStations,
                ),
                const Divider(height: 1),
                _manageRow(
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: PsEvColors.amber,
                  title: 'Wallet & Top-Up',
                  subtitle: 'Balance, transactions, and top-up',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                ),
                const Divider(height: 1),
                _manageRow(
                  icon: Icons.list_alt,
                  iconColor: PsEvColors.slateText,
                  title: 'Booking History',
                  subtitle: 'Your past and ongoing bookings',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookingsScreen())),
                  isLast: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Account Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: PsEvColors.mutedText)),
          ),
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
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Enter your mobile number';
                              if (!RegExp(r'^\d{11}$').hasMatch(v.trim())) return 'Must be exactly 11 digits';
                              return null;
                            },
                          ),
                        ),
                      ],
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

  Widget _manageRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isLast ? Radius.zero : Radius.zero,
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
