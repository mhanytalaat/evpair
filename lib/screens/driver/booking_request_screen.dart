import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../models/charger_profile.dart';
import '../../models/availability_slot.dart';
import '../../models/enums.dart';
import '../../services/booking_service.dart';
import '../../services/wallet_service.dart';
import '../../services/pricing_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import 'topup_screen.dart';
import 'booking_status_screen.dart';

/// Pushed screen: confirm-booking. Registration is ensured BEFORE this
/// screen is pushed (see driver_home_screen.dart's "Request" button).
///
/// NOTE on the wallet-balance fix: `total` here uses
/// PricingService.computeCost(), which now rounds to a whole EGP amount.
/// The exact same rounded value is used again inside
/// BookingService.createRequest() when actually holding funds - so the
/// number shown here always matches exactly what gets compared against
/// the wallet balance, eliminating the previous "I have enough money but
/// it still asks me to top up" mismatch (which was caused by comparing an
/// unrounded floating-point total against a rounded, displayed one).
class BookingRequestScreen extends StatelessWidget {
  final ChargerProfile charger;
  final AvailabilitySlot slot;

  const BookingRequestScreen({super.key, required this.charger, required this.slot});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final wallet = context.watch<WalletService>();
    final bookingService = context.read<BookingService>();

    final minutes = slot.durationMinutes.toDouble();
    final total = PricingService.computeCost(model: charger.pricingModel, price: charger.price, powerKw: charger.powerKw, minutes: minutes);
    final balance = wallet.balanceOf(kCurrentUserId);
    final ok = balance >= total;
    final dateFmt = DateFormat('EEE, MMM d • h:mm a');

    final rateLine = charger.pricingModel == PricingModel.perKwh
        ? '${minutes.toStringAsFixed(0)} min ≈ ${(charger.powerKw * minutes / 60).toStringAsFixed(2)} kWh × ${charger.priceLabel}'
        : '${minutes.toStringAsFixed(0)} min × ${charger.priceLabel}';

    return Scaffold(
      appBar: const PsEvAppBar(title: 'Confirm Booking'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(charger.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('${dateFmt.format(slot.start)} – ${DateFormat('h:mm a').format(slot.end)}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                  Text(rateLine, style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text('${total.toStringAsFixed(0)} EGP held (estimate)', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 10),
                    child: Text(
                      'You will only be charged for the actual time you charge — any unused amount is refunded automatically once the session ends.',
                      style: TextStyle(fontSize: 11, color: PsEvColors.mutedText),
                    ),
                  ),
                  Text('Wallet balance: ${balance.toStringAsFixed(0)} EGP', style: const TextStyle(fontSize: 13)),
                  if (!ok)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Insufficient balance — you will be asked to top up.', style: TextStyle(fontSize: 12, color: PsEvColors.red)),
                    ),
                  const SizedBox(height: 12),
                  PsEvFilledButton(
                    label: ok ? 'Send Booking Request' : 'Top Up Wallet',
                    onTap: () {
                      if (!ok) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => TopUpScreen(suggestedAmount: total - balance)));
                        return;
                      }
                      try {
                        final booking = bookingService.createRequest(
                          driverId: kCurrentUserId,
                          charger: charger,
                          slot: slot,
                          driverCommunity: app.car?.community,
                        );
                        app.setLastDriverBooking(booking.id);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: booking.id)));
                      } on ChargerAccessDeniedException catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: PsEvColors.red));
                      }
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
