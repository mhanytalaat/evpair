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

/// Pushed screen: confirm-booking with a CUSTOM time range picker. The
/// host's free window (e.g. 10:00 AM - 10:00 PM) is shown as the outer
/// boundary, and the driver can narrow it down to any sub-range within
/// that boundary (e.g. 2:00 PM - 4:00 PM) using the two time pickers
/// below. Defaults to the FULL host window.
class BookingRequestScreen extends StatefulWidget {
  final ChargerProfile charger;
  final AvailabilitySlot slot;

  const BookingRequestScreen({super.key, required this.charger, required this.slot});

  @override
  State<BookingRequestScreen> createState() => _BookingRequestScreenState();
}

class _BookingRequestScreenState extends State<BookingRequestScreen> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay.fromDateTime(widget.slot.start);
    _endTime = TimeOfDay.fromDateTime(widget.slot.end);
  }

  DateTime _combine(DateTime baseDate, TimeOfDay t) =>
      DateTime(baseDate.year, baseDate.month, baseDate.day, t.hour, t.minute);

  ({DateTime start, DateTime end}) _resolveRange() {
    final start = _combine(widget.slot.start, _startTime);
    var end = _combine(widget.slot.start, _endTime);
    if (!end.isAfter(start)) {
      final slotSpansMidnight = widget.slot.end.day != widget.slot.start.day;
      if (slotSpansMidnight) {
        end = end.add(const Duration(days: 1));
      }
    }
    return (start: start, end: end);
  }

  Future<void> _pickStart(BuildContext context) async {
    final picked = await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEnd(BuildContext context) async {
    final picked = await showTimePicker(context: context, initialTime: _endTime);
    if (picked != null) setState(() => _endTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final wallet = context.watch<WalletService>();
    final bookingService = context.read<BookingService>();
    final charger = widget.charger;
    final slot = widget.slot;

    final range = _resolveRange();
    final minutes = range.end.difference(range.start).inMinutes;
    final withinBounds = slot.canFit(range.start, range.end);
    final meetsMinimum = minutes >= kMinBookingMinutes;
    final rangeValid = withinBounds && meetsMinimum;

    final total = rangeValid
        ? PricingService.computeCost(model: charger.pricingModel, price: charger.price, powerKw: charger.powerKw, minutes: minutes.toDouble())
        : 0.0;
    final balance = wallet.balanceOf(kCurrentUserId);
    final canAfford = balance >= total;

    final dateFmt = DateFormat('EEE, MMM d');
    final timeFmt = DateFormat('h:mm a');

    final rateLine = rangeValid
        ? (charger.pricingModel == PricingModel.perKwh
            ? '${minutes.toStringAsFixed(0)} min ≈ ${(charger.powerKw * minutes / 60).toStringAsFixed(2)} kWh × ${charger.priceLabel}'
            : '$minutes min × ${charger.priceLabel}')
        : '';

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
                  Text('${charger.city} • ${charger.area}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: PsEvColors.emeraldPale, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: PsEvColors.emeraldChipText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Host is free ${dateFmt.format(slot.start)}, ${timeFmt.format(slot.start)} – ${timeFmt.format(slot.end)}. '
                            'Choose any time range within this window below.',
                            style: const TextStyle(color: PsEvColors.emeraldChipText, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('Your charging start time', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 6),
                  PsEvFilledButton(
                    icon: Icons.schedule,
                    label: _startTime.format(context),
                    onTap: () => _pickStart(context),
                  ),
                  const SizedBox(height: 12),

                  const Text('Your charging end time', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 6),
                  PsEvFilledButton(
                    icon: Icons.schedule,
                    label: _endTime.format(context),
                    onTap: () => _pickEnd(context),
                  ),

                  if (!rangeValid) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: PsEvColors.redChip, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 16, color: PsEvColors.redChipText),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              !withinBounds
                                  ? 'Your chosen time must be fully within the host\'s free window (${timeFmt.format(slot.start)} – ${timeFmt.format(slot.end)}).'
                                  : 'Minimum booking duration is $kMinBookingMinutes minutes.',
                              style: const TextStyle(color: PsEvColors.redChipText, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Text(rateLine, style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('${total.toStringAsFixed(0)} EGP held (estimate)', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const Padding(
                      padding: EdgeInsets.only(top: 6, bottom: 10),
                      child: Text(
                        'You will only be charged for the actual time you charge — any unused amount is refunded automatically once the session ends.',
                        style: TextStyle(fontSize: 11, color: PsEvColors.mutedText),
                      ),
                    ),
                    Text('Wallet balance: ${balance.toStringAsFixed(0)} EGP', style: const TextStyle(fontSize: 13)),
                    if (!canAfford)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Insufficient balance — you will be asked to top up.', style: TextStyle(fontSize: 12, color: PsEvColors.red)),
                      ),
                  ],

                  const SizedBox(height: 12),
                  PsEvFilledButton(
                    label: !rangeValid ? 'Fix Time Range' : (canAfford ? 'Send Booking Request' : 'Top Up Wallet'),
                    onTap: !rangeValid
                        ? null
                        : () {
                            if (!canAfford) {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => TopUpScreen(suggestedAmount: total - balance)));
                              return;
                            }
                            try {
                              final booking = bookingService.createRequest(
                                driverId: kCurrentUserId,
                                charger: charger,
                                requestedStart: range.start,
                                requestedEnd: range.end,
                                driverCommunity: app.car?.community,
                              );
                              app.setLastDriverBooking(booking.id);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: booking.id)));
                            } on BookingRequestException catch (e) {
                              setState(() => _validationError = e.message);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: PsEvColors.red));
                            }
                          },
                  ),
                  if (_validationError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_validationError!, style: const TextStyle(color: PsEvColors.red, fontSize: 12)),
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
