import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../state/app_state.dart';
import '../../models/charger_profile.dart';
import '../../models/enums.dart';
import '../../services/wallet_service.dart';
import '../../services/booking_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import '../auth/register_screen.dart';
import 'my_cars_screen.dart';
import 'wallet_screen.dart';
import 'booking_status_screen.dart';
import 'booking_request_screen.dart';
import 'my_bookings_screen.dart';

enum _ChargerAccessState { standardMismatch, residentsOnlyLocked, full, available }

/// Root tab: driver's landing screen. Each host free window (e.g. 10:00
/// AM - 10:00 PM) is shown as a range with a "Choose Time" button;
/// tapping it opens BookingRequestScreen where the driver picks any
/// custom start/end time within that window.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  String? _selectedChargerId;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  _ChargerAccessState _accessStateFor(ChargerProfile ch, dynamic driverCar) {
    if (driverCar != null && !driverCar.isCompatibleStandard(ch.chargingStandard)) {
      return _ChargerAccessState.standardMismatch;
    }
    if (!ch.isAccessibleToCommunity(driverCar?.community)) {
      return _ChargerAccessState.residentsOnlyLocked;
    }
    return ch.hasAnyFreeSlot ? _ChargerAccessState.available : _ChargerAccessState.full;
  }

  Color _pinColor(_ChargerAccessState state) {
    switch (state) {
      case _ChargerAccessState.standardMismatch:
        return PsEvColors.slateText;
      case _ChargerAccessState.residentsOnlyLocked:
        return PsEvColors.red;
      case _ChargerAccessState.full:
        return PsEvColors.amber;
      case _ChargerAccessState.available:
        return PsEvColors.emerald;
    }
  }

  IconData _pinIcon(_ChargerAccessState state) {
    switch (state) {
      case _ChargerAccessState.standardMismatch:
        return Icons.power_off;
      case _ChargerAccessState.residentsOnlyLocked:
        return Icons.lock;
      case _ChargerAccessState.full:
        return Icons.block;
      case _ChargerAccessState.available:
        return Icons.bolt;
    }
  }

  Future<void> _onChooseTimeTap(BuildContext context, ChargerProfile charger, dynamic slot) async {
    final ok = await ensureRegistered(context);
    if (!ok || !context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => BookingRequestScreen(charger: charger, slot: slot)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wallet = context.watch<WalletService>();
    final bookingService = context.watch<BookingService>();
    final chargers = app.chargers;
    final walletBalance = wallet.balanceOf(kCurrentUserId);
    final activeBooking = app.lastDriverBookingId == null ? null : bookingService.findById(app.lastDriverBookingId!);

    final selected = chargers.firstWhere(
      (c) => c.chargerId == (_selectedChargerId ?? chargers.first.chargerId),
      orElse: () => chargers.first,
    );

    final selectedState = _accessStateFor(selected, app.car);
    final standardMismatch = selectedState == _ChargerAccessState.standardMismatch;
    final residentsLocked = selectedState == _ChargerAccessState.residentsOnlyLocked;
    final bookable = selectedState == _ChargerAccessState.available || selectedState == _ChargerAccessState.full;

    final freeSlots = selected.freeSlots;
    final dateFmt = DateFormat('EEE, MMM d');
    final timeFmt = DateFormat('h:mm a');

    final avgLat = chargers.map((c) => c.latitude).reduce((a, b) => a + b) / chargers.length;
    final avgLng = chargers.map((c) => c.longitude).reduce((a, b) => a + b) / chargers.length;

    return Scaffold(
      appBar: PsEvAppBar(
        title: 'Find a Charger',
        showBrandRow: true,
        actions: [
          const PsEvModePill(label: 'driver mode'),
          PsEvHeaderAction(
            icon: Icons.list_alt,
            tooltip: 'My Bookings',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookingsScreen())),
          ),
          PsEvHeaderAction(
            icon: Icons.account_balance_wallet_outlined,
            tooltip: 'Wallet',
            onPressed: () async {
              final ok = await ensureRegistered(context);
              if (!ok || !context.mounted) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
            },
          ),
          PsEvHeaderAction(
            icon: Icons.electric_car,
            tooltip: 'My Cars',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCarsScreen())),
          ),
          PsEvHeaderAction(
            icon: Icons.smartphone,
            tooltip: 'Last Booking Status',
            onPressed: app.lastDriverBookingId == null
                ? null
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: app.lastDriverBookingId!))),
            disabledMessage: 'No active booking yet. Book a charger first.',
          ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Nearby Chargers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const PsEvTag(label: 'Map View'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(PsEvRadii.mapBox),
                    child: SizedBox(
                      height: 220,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(avgLat, avgLng),
                          initialZoom: 10,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.evpairapp.evpair',
                          ),
                          MarkerLayer(
                            markers: chargers.map((ch) {
                              final state = _accessStateFor(ch, app.car);
                              return Marker(
                                point: LatLng(ch.latitude, ch.longitude),
                                width: 40,
                                height: 40,
                                child: GestureDetector(
                                  onTap: () => setState(() => _selectedChargerId = ch.chargerId),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: _pinColor(state),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: ch.chargerId == selected.chargerId ? Colors.white : Colors.transparent,
                                        width: 3,
                                      ),
                                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                                    ),
                                    child: Icon(_pinIcon(state), color: Colors.white, size: 18),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _legendDot(PsEvColors.emerald, 'Available'),
                      _legendDot(PsEvColors.amber, 'Fully booked'),
                      _legendDot(PsEvColors.red, 'Residents only'),
                      _legendDot(PsEvColors.slateText, 'Different type'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                children: chargers.map((ch) {
                  final state = _accessStateFor(ch, app.car);
                  final pill = switch (state) {
                    _ChargerAccessState.standardMismatch => const PsEvStatusPill(label: 'Different type', background: PsEvColors.slate200, textColor: PsEvColors.slateText),
                    _ChargerAccessState.residentsOnlyLocked => PsEvStatusPill.locked(),
                    _ChargerAccessState.full => PsEvStatusPill.booked(),
                    _ChargerAccessState.available => PsEvStatusPill.free(),
                  };
                  final isSelected = ch.chargerId == selected.chargerId;
                  return InkWell(
                    onTap: () => setState(() => _selectedChargerId = ch.chargerId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: PsEvColors.slate100))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ch.label, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? PsEvColors.emerald : Colors.black87)),
                                Text('${ch.city} • ${ch.area} • ${ch.chargingStandard.shortLabel}', style: const TextStyle(fontSize: 11, color: PsEvColors.mutedText)),
                              ],
                            ),
                          ),
                          pill,
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selected.photoBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(selected.photoBytes!, height: 110, width: double.infinity, fit: BoxFit.cover),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF0D9488)]),
                          borderRadius: BorderRadius.circular(PsEvRadii.iconBox),
                        ),
                        child: const Icon(Icons.ev_station, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(selected.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            Text('${selected.city} • ${selected.area}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                            Wrap(
                              children: [
                                PsEvTag(label: '${selected.powerKw} kW'),
                                PsEvTag(label: selected.chargingStandard.shortLabel),
                                PsEvTag(label: selected.connector.label),
                                PsEvTag.price(label: selected.priceLabel),
                                if (selected.residentsOnly) PsEvTag.restricted(label: '${selected.restrictedCommunity} only'),
                              ],
                            ),
                            if (selected.mapLink != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: InkWell(
                                  onTap: () async {
                                    final uri = Uri.tryParse(selected.mapLink!);
                                    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  },
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_on, size: 13, color: PsEvColors.emerald),
                                      SizedBox(width: 4),
                                      Text('Open in Google Maps', style: TextStyle(color: PsEvColors.emerald, fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (standardMismatch)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: PsEvColors.slate200, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          const Icon(Icons.power_off, size: 16, color: PsEvColors.slateText),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This charger uses a different charging type (${selected.chargingStandard.label}) than '
                              'your ${app.car?.chargingStandard.label ?? "car"}. This charger cannot physically charge your car.',
                              style: const TextStyle(color: PsEvColors.slateText, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (residentsLocked)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: PsEvColors.redChip, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          const Icon(Icons.lock, size: 16, color: PsEvColors.redChipText),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This charger is restricted to ${selected.restrictedCommunity} residents. Update your community in Car Profile if this applies to you.',
                              style: const TextStyle(color: PsEvColors.redChipText, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: PsEvColors.emeraldPale, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 16, color: PsEvColors.emeraldChipText),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Compatible with your ${app.car?.carModel ?? "car"} '
                              '(${app.car?.chargingStandard.shortLabel ?? "-"}, '
                              '${app.car?.connector.label ?? "-"}, '
                              '${app.car?.maxAmpere.toStringAsFixed(0) ?? "-"}A)',
                              style: const TextStyle(color: PsEvColors.emeraldChipText, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (bookable) ...[
                    const SizedBox(height: 12),
                    const Text('Host Free Windows', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Padding(
                      padding: EdgeInsets.only(top: 2, bottom: 4),
                      child: Text('Tap "Choose Time" to pick any custom range within a window.', style: TextStyle(fontSize: 11, color: PsEvColors.mutedText)),
                    ),
                    if (freeSlots.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('No free windows right now for this charger.', style: TextStyle(color: PsEvColors.mutedText)),
                      )
                    else
                      ...freeSlots.map((s) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(dateFmt.format(s.start), style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                                      Text('${timeFmt.format(s.start)} – ${timeFmt.format(s.end)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      if (s.recurrenceLabel != null)
                                        Text(s.recurrenceLabel!, style: const TextStyle(fontSize: 10, color: PsEvColors.emerald)),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                                  onPressed: () => _onChooseTimeTap(context, selected, s),
                                  child: const Text('Choose Time', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          )),
                  ],
                ],
              ),
            ),
          ),

          _buildDashboardSection(
            context: context,
            walletBalance: walletBalance,
            carLabel: app.car?.carModel ?? 'No car added yet',
            carDetails: app.car == null
                ? 'Add a car to check charger compatibility'
                : '${app.car!.chargingStandard.shortLabel} • ${app.car!.connector.label} • ${app.car!.maxAmpere.toStringAsFixed(0)}A',
            bookingText: activeBooking == null ? 'No active booking' : activeBooking.status.name,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardSection({
    required BuildContext context,
    required double walletBalance,
    required String carLabel,
    required String carDetails,
    required String bookingText,
  }) {
    final app = context.read<AppState>();
    return Column(
      children: [
        _dashboardCard(
          icon: '💰',
          title: 'My Wallet',
          subtitle: '${walletBalance.toStringAsFixed(0)} EGP',
          buttonText: 'Top Up (InstaPay / Vodafone Cash)',
          onTap: () async {
            final ok = await ensureRegistered(context);
            if (!ok || !context.mounted) return;
            Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
          },
        ),
        _dashboardCard(
          icon: '🚗',
          title: 'My Car Profile',
          subtitle: '$carLabel • $carDetails',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCarsScreen())),
        ),
        _dashboardCard(
          icon: '🔍',
          title: 'Find a Compatible Charger',
          subtitle: 'Filtered by ampere, connector, distance & availability',
          onTap: () => _scrollController.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
        ),
        _dashboardCard(
          icon: '📋',
          title: 'My Booking Status',
          subtitle: bookingText,
          onTap: () {
            if (app.lastDriverBookingId == null) return;
            Navigator.push(context, MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: app.lastDriverBookingId!)));
          },
        ),
      ],
    );
  }

  Widget _dashboardCard({
    required String icon,
    required String title,
    required String subtitle,
    String? buttonText,
    VoidCallback? onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(PsEvRadii.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: PsEvColors.emeraldPale, shape: BoxShape.circle),
                    child: Text(icon, style: const TextStyle(fontSize: 23)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black)),
                        const SizedBox(height: 4),
                        Text(subtitle, style: const TextStyle(fontSize: 13, color: PsEvColors.mutedText)),
                      ],
                    ),
                  ),
                ],
              ),
              if (buttonText != null) ...[
                const SizedBox(height: 16),
                PsEvFilledButton(label: buttonText, onTap: onTap),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: PsEvColors.mutedText)),
      ],
    );
  }
}
