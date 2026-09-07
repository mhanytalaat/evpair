import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../models/charger_profile.dart';
import '../../models/availability_slot.dart';
import '../../models/enums.dart';
import '../../services/booking_service.dart';
import '../../services/wallet_service.dart';
import '../../services/auth_service.dart';
import '../../services/pricing_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import 'topup_screen.dart';
import 'booking_status_screen.dart';
import 'car_setup_screen.dart';

/// Pushed screen: confirm-booking with a CUSTOM time range picker. The
/// host's free window (e.g. 10:00 AM - 10:00 PM) is shown as the outer
/// boundary, and the driver can narrow it down to any sub-range within
/// that boundary (e.g. 2:00 PM - 4:00 PM) using the two time pickers
/// below. Defaults to the FULL host window.
///
/// Two fixes from the 31/8 update, both implemented WITHOUT any new
/// global "draft" state - by simply keeping this screen on the
/// Navigator stack while pushing a follow-up screen on top of it:
///
///   1. "If I haven't selected a car, I can't book" is still enforced
///      (correct - a booking legitimately needs car details), but is now
///      a friendly recommendation dialog with a direct shortcut to Add
///      Car, instead of an abrupt red error surfacing deep inside
///      BookingService.createRequest. Since CarSetupScreen is PUSHED
///      (not used to replace this screen), popping it returns here with
///      every chosen value (time range, etc.) still fully intact.
///   2. "I have to redo my choices after topping up" is fixed the same
///      way: TopUpScreen is pushed on top of this screen, and now pops
///      straight back here on submit (see topup_screen.dart) instead of
///      navigating away to a separate status screen and then all the
///      way back to the root map.
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
  bool _submitting = false;

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

  /// Item #3 of the 31/8 update: friendly recommendation instead of a
  /// hard block. Returns true if the driver now HAS a car (either they
  /// already had one, or they just added one and popped back here), or
  /// false if they dismissed the dialog without adding one.
  Future<bool> _ensureCarOrPrompt(BuildContext context) async {
    final app = context.read<AppState>();
    if (app.car != null) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a car to continue'),
        content: const Text(
          "We recommend adding your car before booking - the host uses your car's plate number and "
          'connector details to confirm it\'s really you when you arrive. It only takes a minute.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'later'), child: const Text('Not Now')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'add'), child: const Text('Add a Car')),
        ],
      ),
    );
    if (choice != 'add' || !context.mounted) return false;
    // Pushed on top of THIS screen - popping it (see CarSetupScreen's
    // _submit) returns here with the chosen time range still intact.
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CarSetupScreen()));
    return result != null && context.mounted && context.read<AppState>().car != null;
  }

  Future<void> _onTopUpTap(BuildContext context, double amountNeeded) async {
    // Pushed (not replaced) - see topup_screen.dart, which now pops
    // straight back here on submit instead of navigating to a separate
    // status screen. No draft/state-restoration code needed: this
    // screen's State object is simply paused, not disposed, while
    // TopUpScreen is on top of it.
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TopUpScreen(suggestedAmount: amountNeeded)));
    if (mounted) setState(() {}); // refresh in case balance/UI needs it
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final auth = context.watch<AuthService>();
    final wallet = context.watch<WalletService>();
    final bookingService = context.read<BookingService>();
    final charger = widget.charger;
    final slot = widget.slot;

    final range = _resolveRange();
    final minutes = range.end.difference(range.start).inMinutes;
    final withinBounds = slot.canFit(range.start, range.end);
    final meetsMinimum = minutes >= kMinBookingMinutes;
    // FIX (7/9 update, item #8): reject a past start time right in the
    // picker's validation instead of only on submit.
    final isPastStart = range.start.isBefore(DateTime.now());
    final rangeValid = withinBounds && meetsMinimum && !isPastStart;
    final total = rangeValid
        ? PricingService.computeCost(model: charger.pricingModel, price: charger.price, powerKw: charger.powerKw, minutes: minutes.toDouble())
        : 0.0;
    final balance = wallet.balanceOf(app.currentUserId ?? '');
    final canAfford = balance >= total;
    final dateFmt = DateFormat('EEE, MMM d');
    final timeFmt = DateFormat('h:mm a');
    // Item #6 of the 31/8 update: show exactly which sub-ranges within
    // this window are already booked, instead of only surfacing a
    // generic "not available" error after the driver picks a
    // conflicting time and taps Send.
    final bookedRanges = context.watch<BookingService>().bookedRangesFor(charger.chargerId)
        .where((r) => !r.end.isBefore(slot.start) && !r.start.isAfter(slot.end))
        .toList();
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
                  if (bookedRanges.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: PsEvColors.amberChip, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.event_busy, size: 15, color: PsEvColors.amberChipText),
                                SizedBox(width: 6),
                                Text('Already booked in this window:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: PsEvColors.amberChipText)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ...bookedRanges.map((r) => Text(
                                  '${timeFmt.format(r.start)} – ${timeFmt.format(r.end)}',
                                  style: const TextStyle(fontSize: 12, color: PsEvColors.amberChipText),
                                )),
                          ],
                        ),
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

                              isPastStart
                                  ? "This time has already passed - please choose a current or upcoming time."
                                  : (!withinBounds
                                      ? "Your chosen time must be fully within the host's free window (${timeFmt.format(slot.start)} - ${timeFmt.format(slot.end)})."
                                      : 'Minimum booking duration is $kMinBookingMinutes minutes.'),
                                      
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
                    label: _submitting
                        ? 'Please wait...'
                        : (!rangeValid ? 'Fix Time Range' : (canAfford ? 'Send Booking Request' : 'Top Up Wallet')),
                    onTap: !rangeValid || _submitting
                        ? null
                        : () async {
                            if (!canAfford) {
                              await _onTopUpTap(context, total - balance);
                              return;
                            }
                            final hasCar = await _ensureCarOrPrompt(context);
                            if (!hasCar || !context.mounted) return;
                            setState(() => _submitting = true);
                            try {
                              final activeCar = context.read<AppState>().car!;
                              final booking = await bookingService.createRequest(
                                driverId: app.currentUserId ?? '',
                                driverName: auth.displayName,
                                charger: charger,
                                requestedStart: range.start,
                                requestedEnd: range.end,
                                driverCommunity: activeCar.community,
                                driverCar: activeCar,
                              );
                              app.setLastDriverBooking(booking.id);
                              if (!context.mounted) return;
                              Navigator.push(context, MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: booking.id)));
                            } on BookingRequestException catch (e) {
                              setState(() {
                                _validationError = e.message;
                                _submitting = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: PsEvColors.red));
                            } catch (e) {
                              setState(() => _submitting = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Could not send booking request: $e'), backgroundColor: PsEvColors.red),
                              );
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
