import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../services/wallet_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import 'topup_screen.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final balance = wallet.balanceOf(kCurrentUserId);

    return Scaffold(
      appBar: const PsEvAppBar(title: 'My Wallet'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, color: PsEvColors.emerald, size: 20),
                      SizedBox(width: 8),
                      Text('My Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('${balance.toStringAsFixed(0)} EGP', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  PsEvFilledButton(
                    label: 'Top Up (InstaPay / Vodafone Cash)',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TopUpScreen())),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Transaction history', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          ...wallet.ledgerFor(kCurrentUserId).map((e) => Card(
                child: ListTile(
                  leading: Icon(
                    e.amount >= 0 ? Icons.arrow_downward : Icons.arrow_upward,
                    color: e.amount >= 0 ? PsEvColors.emerald : PsEvColors.red,
                  ),
                  title: Text(e.reason, style: const TextStyle(fontSize: 13)),
                  trailing: Text(
                    '${e.amount >= 0 ? '+' : ''}${e.amount.toStringAsFixed(0)} EGP',
                    style: TextStyle(color: e.amount >= 0 ? PsEvColors.emerald : PsEvColors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
