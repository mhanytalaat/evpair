import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../services/wallet_service.dart';
import '../../models/enums.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import 'topup_status_screen.dart';

class TopUpScreen extends StatefulWidget {
  final double suggestedAmount;
  const TopUpScreen({super.key, this.suggestedAmount = 300});

  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> {
  late final _amountCtrl = TextEditingController(text: widget.suggestedAmount.toStringAsFixed(0));
  final _refCtrl = TextEditingController();
  PaymentMethod _method = PaymentMethod.instapay;

  @override
  Widget build(BuildContext context) {
    final wallet = context.read<WalletService>();

    return Scaffold(
      appBar: const PsEvAppBar(title: 'Top Up Wallet'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Send the amount via InstaPay or Vodafone Cash, then submit proof. Admin will review and approve before your wallet is credited.',
                    style: TextStyle(fontSize: 12, color: PsEvColors.mutedText),
                  ),
                  const SizedBox(height: 14),
                  const Text('Payment method', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<PaymentMethod>(
                    value: _method,
                    items: const [
                      DropdownMenuItem(value: PaymentMethod.instapay, child: Text('InstaPay')),
                      DropdownMenuItem(value: PaymentMethod.vodafoneCash, child: Text('Vodafone Cash')),
                      DropdownMenuItem(value: PaymentMethod.other, child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _method = v!),
                  ),
                  const SizedBox(height: 10),
                  const Text('Amount (EGP)', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  TextField(controller: _amountCtrl, keyboardType: TextInputType.number),
                  const SizedBox(height: 10),
                  const Text('Reference number', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  TextField(controller: _refCtrl, decoration: const InputDecoration(hintText: 'INST-2026-993421')),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Upload proof screenshot ✓'),
                  ),
                  const SizedBox(height: 12),
                  PsEvFilledButton(
                    label: 'Submit Top-Up Request',
                    onTap: () {
                      wallet.submitTopUp(
                        driverId: kCurrentUserId,
                        amount: double.tryParse(_amountCtrl.text) ?? widget.suggestedAmount,
                        method: _method,
                        referenceNote: _refCtrl.text.trim().isEmpty ? 'N/A' : _refCtrl.text.trim(),
                        proofImagePath: 'proof_screenshot.jpg',
                      );
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TopUpStatusScreen()));
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
