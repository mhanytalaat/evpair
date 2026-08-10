import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../services/wallet_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';

class TopUpStatusScreen extends StatelessWidget {
  const TopUpStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final pending = wallet.pendingTopUps.where((t) => t.driverId == kCurrentUserId).isNotEmpty;
    final balance = wallet.balanceOf(kCurrentUserId);

    return Scaffold(
      appBar: const PsEvAppBar(title: 'Top-Up Status'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: pending
                    ? [
                        const Icon(Icons.hourglass_top, size: 40, color: PsEvColors.amber),
                        const SizedBox(height: 8),
                        const Text('Waiting for admin approval...'),
                        const Text('An admin needs to review your proof before crediting your wallet.',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                      ]
                    : [
                        const Icon(Icons.check_circle, size: 40, color: PsEvColors.emerald),
                        const SizedBox(height: 8),
                        const Text('Approved! Wallet credited.'),
                        Text('New balance: ${balance.toStringAsFixed(0)} EGP', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        PsEvFilledButton(
                          label: 'Back to Chargers',
                          onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
                        ),
                      ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
