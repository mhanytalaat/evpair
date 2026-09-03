import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../services/wallet_service.dart';
import '../../models/enums.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';

/// FIX (31/8 update): "Upload proof screenshot" previously did nothing at
/// all - its button was wired to an EMPTY callback (`onPressed: () {}`),
/// so tapping it never opened an image picker, and top-up requests were
/// always submitted with a fake hardcoded `proofImagePath` string and no
/// actual image. This screen now:
///   1. Actually opens the camera/gallery via image_picker and shows a
///      preview thumbnail of the attached screenshot.
///   2. Requires a screenshot to be attached before "Submit" is enabled.
///   3. Pops back to whichever screen pushed this one (Wallet screen, OR
///      BookingRequestScreen when reached via "insufficient balance")
///      instead of navigating to a separate status screen and then all
///      the way back to the root map - this is what fixes "I have to
///      redo all my choices again" when topping up mid-booking: since
///      BookingRequestScreen is never popped off the stack, its chosen
///      time range/station selection is preserved automatically by
///      Flutter's Navigator, with zero extra state-management code
///      needed.
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
  Uint8List? _proofBytes;
  bool _submitting = false;

  Future<void> _pickProof() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose Screenshot from Gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 80);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _proofBytes = bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load that image: $e'), backgroundColor: PsEvColors.red),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_proofBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please attach a screenshot of your payment before submitting.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    setState(() => _submitting = true);
    final wallet = context.read<WalletService>();
    final currentUserId = context.read<AppState>().currentUserId ?? '';
    wallet.submitTopUp(
      driverId: currentUserId,
      amount: amount,
      method: _method,
      referenceNote: _refCtrl.text.trim().isEmpty ? 'N/A' : _refCtrl.text.trim(),
      proofImagePath: 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg',
      proofImageBase64: base64Encode(_proofBytes!),
    );
    if (!mounted) return;
    // Pop back to whatever pushed this screen (Wallet screen, or
    // BookingRequestScreen if the driver got here via "insufficient
    // balance") - see class doc above for why this matters.
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✅ Top-up submitted! You'll get a notification the moment it's approved."),
        backgroundColor: PsEvColors.emerald,
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 12),
                  if (_proofBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_proofBytes!, height: 160, width: double.infinity, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: _pickProof,
                    icon: Icon(_proofBytes == null ? Icons.image_outlined : Icons.check_circle, color: _proofBytes == null ? null : PsEvColors.emerald),
                    label: Text(_proofBytes == null ? 'Upload proof screenshot' : 'Change proof screenshot'),
                  ),
                  if (_proofBytes == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Required - attach a screenshot of your InstaPay/Vodafone Cash confirmation.', style: TextStyle(fontSize: 11, color: PsEvColors.red)),
                    ),
                  const SizedBox(height: 12),
                  PsEvFilledButton(
                    label: _submitting ? 'Submitting...' : 'Submit Top-Up Request',
                    onTap: _submitting ? null : _submit,
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
