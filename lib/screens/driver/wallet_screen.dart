import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../services/wallet_service.dart';
import '../../models/enums.dart';
import '../../models/wallet_transaction.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import 'topup_screen.dart';

/// FIX (9/24 update, item #10 - "there is no topup history showing
/// pending or approved or anything... once approved needs to be shown
/// in the wallet history"): root cause found - this screen's
/// "Transaction history" section only ever showed `WalletLedgerEntry`
/// rows, which are ONLY ever created once a top-up is actually
/// APPROVED (an "amount credited" line, via
/// WalletService.reviewTopUp). A still-PENDING or a REJECTED top-up
/// request was never shown anywhere the driver could see - there was
/// no visibility into "did my request even go through, is it still
/// waiting, or was it rejected?". A separate TopUpStatusScreen already
/// existed in the codebase for exactly this purpose, but nothing in
/// the app ever navigated to it, so it was effectively unreachable.
///
/// FIX: added a new "My Top-Up Requests" section, backed by the new
/// `WalletService.topUpsForDriver()` getter, showing every request
/// this driver has ever submitted with a clear status pill (Pending
/// Approval / Approved / Rejected) - independent of the ledger, so a
/// pending request is visible immediately on submission, and stays
/// visible (marked Approved/Rejected) after review. The notification
/// on approval/rejection already existed and is unchanged (see
/// WalletService.reviewTopUp) - this only fixes the "shown in wallet
/// history" visibility gap.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  PsEvStatusPill _pillFor(TopUpStatus status) {
    switch (status) {
      case TopUpStatus.pendingProofReview:
        return const PsEvStatusPill(label: 'Pending Approval', background: PsEvColors.amberChip, textColor: PsEvColors.amberChipText);
      case TopUpStatus.approved:
        return const PsEvStatusPill(label: 'Approved', background: PsEvColors.emeraldChip, textColor: PsEvColors.emeraldChipText);
      case TopUpStatus.rejected:
        return const PsEvStatusPill(label: 'Rejected', background: PsEvColors.redChip, textColor: PsEvColors.redChipText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final currentUserId = context.watch<AppState>().currentUserId ?? '';
    final balance = wallet.balanceOf(currentUserId);
    final myTopUps = wallet.topUpsForDriver(currentUserId);
    final dateFmt = DateFormat('MMM d, h:mm a');

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
          const Text('My Top-Up Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          if (myTopUps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No top-up requests yet.', style: TextStyle(color: PsEvColors.mutedText)),
            )
          else
            ...myTopUps.map((t) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${t.amount.toStringAsFixed(0)} EGP via ${t.method.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Ref: ${t.referenceNote}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11)),
                              Text(dateFmt.format(t.requestedAt), style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11)),
                              if (t.status != TopUpStatus.pendingProofReview && t.adminNote != null && t.adminNote!.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('Note: ${t.adminNote}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11)),
                                ),
                            ],
                          ),
                        ),
                        _pillFor(t.status),
                      ],
                    ),
                  ),
                )),
          const SizedBox(height: 8),
          const Text('Transaction history', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          ...wallet.ledgerFor(currentUserId).map((e) => Card(
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
