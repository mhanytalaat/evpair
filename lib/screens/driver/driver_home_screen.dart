import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../../state/app_state.dart';
import '../../models/charger_profile.dart';
import '../../models/booking.dart';
import '../../models/enums.dart';
import '../../services/auth_service.dart';
import '../../services/wallet_service.dart';
import '../../services/booking_service.dart';
import '../../services/notification_service.dart';
import '../../services/map_launcher_service.dart';
import '../../services/profile_photo_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../widgets/host_rating_badge.dart';
import '../auth/register_screen.dart';
import '../profile/profile_screen.dart';
import '../shared/location_picker_field.dart';
import '../shared/notifications_screen.dart';
import 'my_cars_screen.dart';
import '../host/host_home_screen.dart';
import '../partner/home_installation_screen.dart';
import 'wallet_screen.dart';
import 'booking_status_screen.dart';
import 'booking_request_screen.dart';
import 'my_bookings_screen.dart' show MyBookingsScreen, BookingsViewMode;
import '../shared/station_reviews_screen.dart';

enum _ChargerAccessState { standardMismatch, residentsOnlyLocked, full, available }

/// Root/home screen. Full-screen map with a floating search/filter bar,
/// a notification bell (with unread badge), a recenter button, a
/// quick-add "+" button, a live-session banner, a draggable bottom sheet
/// with the station list/detail/booking, and a floating 4-icon footer
/// nav (Map / Sessions / Wallet / Profile, the last showing a
/// notification-count badge too).
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});
  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  String? _selectedChargerId;
  String? _selectedCity;
  String? _selectedArea;
  bool _onlyAvailable = false;
  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController = DraggableScrollableController();

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

  void _expandSheet() {
    _sheetController.animateTo(0.6, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _collapseSheet() {
    _sheetController.animateTo(0.4, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _showLocationMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _recenterToMyLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationMessage('Please enable Location Services to find your position.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationMessage('Location permission denied.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showLocationMessage('Location permission is disabled. Enable it in Settings to recenter the map.');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      _mapController.move(LatLng(position.latitude, position.longitude), 14);
    } catch (e) {
      _showLocationMessage('Could not get your location right now.');
    }
  }

  void _showFilterSheet(BuildContext context) {
    final app = context.read<AppState>();
    final auth = context.read<AuthService>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 4,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Filter Stations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      const SizedBox(height: 14),
                      LocationPickerField(
                        governorate: _selectedCity,
                        area: _selectedArea,
                        showAllOption: true,
                        userId: app.currentUserId ?? '',
                        userName: auth.displayName,
                        onGovernorateChanged: (v) {
                          setState(() {
                            _selectedCity = v;
                            _selectedArea = null;
                            _selectedChargerId = null;
                          });
                          setSheetState(() {});
                        },
                        onAreaChanged: (v) {
                          setState(() {
                            _selectedArea = v;
                            _selectedChargerId = null;
                          });
                          setSheetState(() {});
                        },
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _onlyAvailable,
                        activeColor: PsEvColors.emerald,
                        title: const Text('Only show stations with a free slot', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Hides fully booked stations from the map and list', style: TextStyle(fontSize: 11, color: PsEvColors.mutedText)),
                        onChanged: (value) {
                          setState(() {
                            _onlyAvailable = value;
                            _selectedChargerId = null;
                          });
                          setSheetState(() {});
                        },
                      ),
                      const SizedBox(height: 10),
                      if (_selectedCity != null || _selectedArea != null || _onlyAvailable)
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedCity = null;
                              _selectedArea = null;
                              _onlyAvailable = false;
                            });
                            setSheetState(() {});
                          },
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear filters'),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Show Stations'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showQuickAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              20 + MediaQuery.of(sheetContext).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quick Add', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 14),
                _quickAddTile(
                  icon: Icons.electric_car,
                  iconColor: PsEvColors.emerald,
                  title: 'Add a Car',
                  subtitle: 'Register a new vehicle to your account',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCarsScreen()));
                  },
                ),
                const SizedBox(height: 10),
                _quickAddTile(
                  icon: Icons.ev_station,
                  iconColor: PsEvColors.blue,
                  title: 'Add a Station',
                  subtitle: 'List a charging station you host',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final ok = await ensureRegistered(context);
                    if (!ok || !context.mounted) return;
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HostHomeScreen()));
                  },
                ),
                const SizedBox(height: 10),
                _quickAddTile(
                  icon: Icons.build_circle_outlined,
                  iconColor: PsEvColors.amber,
                  title: 'Check Equipment',
                  subtitle: 'Browse cables, adaptors & stations, or request a service',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final ok = await ensureRegistered(context);
                    if (!ok || !context.mounted) return;
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeInstallationScreen()));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickAddTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: PsEvColors.slate100, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: iconColor.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(subtitle, style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: PsEvColors.mutedText),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wallet = context.watch<WalletService>();
    final bookingService = context.watch<BookingService>();
    final auth = context.watch<AuthService>();
    final notificationService = context.watch<NotificationService>();

    final allChargers = app.chargers;
    final walletBalance = wallet.balanceOf(app.currentUserId ?? '');
    // FIX (7/9 update, items #4/#9/#15): derive the active booking from
    // a LIVE Firestore-backed query instead of the ephemeral
    // AppState.lastDriverBookingId (which is never persisted and resets
    // to null on every app restart / re-sign-in).
    final driverActiveBookings = bookingService.activeForDriver(app.currentUserId ?? '');
    final activeBooking = driverActiveBookings.isEmpty ? null : driverActiveBookings.first;
    final hasActiveBooking = activeBooking != null;
          // NEW (9/15 update): surfaces host-side pending requests / running
      // sessions right on the home map, so a host doesn't have to open
      // My Stations -> a specific charger just to see or act on these.
      final hostPendingApprovals = bookingService.pendingApprovalsForHost(app.currentUserId ?? '');
      final hostInProgress = bookingService.inProgressForHost(app.currentUserId ?? '');
      final hasHostPending = hostPendingApprovals.isNotEmpty;
      final hasHostRunning = hostInProgress.isNotEmpty;

    final chargers = allChargers.where((c) {
      if (_selectedCity != null && c.city != _selectedCity) return false;
      if (_selectedArea != null && c.area != _selectedArea) return false;
      if (_onlyAvailable && !c.hasAnyFreeSlot) return false;
      return true;
    }).toList();
    final filtersActive = _selectedCity != null || _selectedArea != null || _onlyAvailable;
    final searchLabel = _selectedArea != null
        ? '${_selectedArea!}, ${_selectedCity!}'
        : (_selectedCity ?? 'Find a charging station');
    if (allChargers.isEmpty) {
      return Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.ev_station, size: 48, color: PsEvColors.mutedText),
                      const SizedBox(height: 12),
                      const Text('No chargers available yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      const Text(
                        'Once a host adds a charging station, it will show up here for booking.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: PsEvColors.mutedText, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 16,
              child: _notificationBell(context, notificationService),
            ),
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 92,
              child: _quickAddButton(context),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: _buildFloatingFooter(context, app, auth, hasActiveBooking, notificationService),
            ),
          ],
        ),
      );
    }
    final selected = chargers.isEmpty
        ? null
        : chargers.firstWhere(
            (c) => c.chargerId == (_selectedChargerId ?? chargers.first.chargerId),
            orElse: () => chargers.first,
          );
    final selectedState = selected == null ? null : _accessStateFor(selected, app.car);
    final standardMismatch = selectedState == _ChargerAccessState.standardMismatch;
    final residentsLocked = selectedState == _ChargerAccessState.residentsOnlyLocked;
    final bookable = selectedState == _ChargerAccessState.available || selectedState == _ChargerAccessState.full;
    final freeSlots = selected?.freeSlots ?? const [];
    final dateFmt = DateFormat('EEE, MMM d');
    final timeFmt = DateFormat('h:mm a');
    final avgLat = allChargers.map((c) => c.latitude).reduce((a, b) => a + b) / allChargers.length;
    final avgLng = allChargers.map((c) => c.longitude).reduce((a, b) => a + b) / allChargers.length;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(avgLat, avgLng),
                initialZoom: 11,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.evpairapp.evpair',
                  maxNativeZoom: 19,
                  errorTileCallback: (tile, error, stackTrace) {
                    debugPrint('Map tile failed to load (${tile.coordinates}): $error');
                  },
                ),
                MarkerLayer(
                  markers: chargers.map((ch) {
                    final state = _accessStateFor(ch, app.car);
                    final isSelected = selected != null && ch.chargerId == selected.chargerId;
                    return Marker(
                      point: LatLng(ch.latitude, ch.longitude),
                      width: 42,
                      height: 42,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedChargerId = ch.chargerId);
                          _expandSheet();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _pinColor(state),
                            shape: BoxShape.circle,
                            border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 3),
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
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    elevation: 4,
                    shadowColor: Colors.black26,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _showFilterSheet(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: PsEvColors.mutedText, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                searchLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: filtersActive ? PsEvColors.slateText : PsEvColors.mutedText,
                                  fontWeight: filtersActive ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (_onlyAvailable)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.bolt, size: 15, color: PsEvColors.emerald),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 4,
                  shadowColor: Colors.black26,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _showFilterSheet(context),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.tune, size: 20, color: PsEvColors.slateText),
                          if (filtersActive)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(color: PsEvColors.emerald, shape: BoxShape.circle),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _notificationBell(context, notificationService),
              ],
            ),
          ),
          if (hasActiveBooking)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 16,
              right: 16,
              child: _buildLiveSessionBanner(context, activeBooking),
            ),
 if (hasHostPending)
            Positioned(
              top: MediaQuery.of(context).padding.top + (hasActiveBooking ? 130 : 70),
              left: 16,
              right: 16,
              child: _buildHostPendingBanner(context, hostPendingApprovals.length),
            ),
          if (hasHostRunning)
            Positioned(
              top: MediaQuery.of(context).padding.top +
                  (hasActiveBooking ? 130 : 70) + (hasHostPending ? 60 : 0),
              left: 16,
              right: 16,
              child: _buildHostRunningBanner(context, hostInProgress.length),
            ),


          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.4,
            minChildSize: 0.18,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12)],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 130),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: PsEvColors.slate200, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${chargers.length} station${chargers.length == 1 ? '' : 's'} found',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (filtersActive)
                          TextButton(
                            onPressed: () => setState(() {
                              _selectedCity = null;
                              _selectedArea = null;
                              _onlyAvailable = false;
                            }),
                            child: const Text('Clear filters', style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                    if (filtersActive)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (_selectedCity != null)
                              Chip(
                                label: Text(_selectedCity!),
                                onDeleted: () => setState(() {
                                  _selectedCity = null;
                                  _selectedArea = null;
                                }),
                              ),
                            if (_selectedArea != null)
                              Chip(
                                label: Text(_selectedArea!),
                                onDeleted: () => setState(() => _selectedArea = null),
                              ),
                            if (_onlyAvailable)
                              Chip(
                                avatar: const Icon(Icons.bolt, size: 14, color: PsEvColors.emerald),
                                label: const Text('Available only'),
                                onDeleted: () => setState(() => _onlyAvailable = false),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (chargers.isEmpty) ...[
                      const SizedBox(height: 20),
                      const Center(
                        child: Column(
                          children: [
                            Icon(Icons.search_off, size: 40, color: PsEvColors.mutedText),
                            SizedBox(height: 10),
                            Text('No stations match these filters', style: TextStyle(fontWeight: FontWeight.bold)),
                            SizedBox(height: 4),
                            Text(
                              'Try a different city, area, or turn off "available only".',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: PsEvColors.mutedText, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
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
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 78,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: chargers.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final ch = chargers[index];
                            final state = _accessStateFor(ch, app.car);
                            final isSelected = selected != null && ch.chargerId == selected.chargerId;
                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => setState(() => _selectedChargerId = ch.chargerId),
                              child: Container(
                                width: 150,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isSelected ? PsEvColors.emeraldPale : PsEvColors.slate100,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: isSelected ? PsEvColors.emerald : Colors.transparent),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(_pinIcon(state), size: 14, color: _pinColor(state)),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            ch.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${ch.city} • ${ch.area}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 10, color: PsEvColors.mutedText),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (selected != null) ...[
                        if (selected.photoBytes != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(selected.photoBytes!, height: 110, width: double.infinity, fit: BoxFit.cover),
                          ),
                        const SizedBox(height: 10),
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

                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(selected.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      ),
                                      HostRatingBadge(hostId: selected.hostId),
                                      // FIX (7/9 update, item #12): opens
                                      // the full list of written reviews
                                      // for this station.
                                      InkWell(
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => StationReviewsScreen(
                                              chargerId: selected.chargerId,
                                              chargerLabel: selected.label,
                                            ),
                                          ),
                                        ),
                                        child: const Padding(
                                          padding: EdgeInsets.only(left: 4, top: 6),
                                          child: Icon(Icons.reviews_outlined, size: 18, color: PsEvColors.mutedText),
                                        ),
                                      ),
                                    ],
                                  ),
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
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: InkWell(
                                      onTap: () => showMapAppChooser(
                                        context,
                                        latitude: selected.latitude,
                                        longitude: selected.longitude,
                                        label: selected.label,
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.location_on, size: 13, color: PsEvColors.emerald),
                                          SizedBox(width: 4),
                                          Text('Get Directions', style: TextStyle(color: PsEvColors.emerald, fontSize: 11)),
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
                            ...freeSlots.map((s) {
                              final booked = bookingService.bookedRangesFor(selected.chargerId)
                                  .where((r) => !r.end.isBefore(s.start) && !r.start.isAfter(s.end))
                                  .toList();
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(dateFmt.format(s.start), style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                                          Text('${timeFmt.format(s.start)} – ${timeFmt.format(s.end)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                          if (s.recurrenceLabel != null)
                                            Text(s.recurrenceLabel!, style: const TextStyle(fontSize: 10, color: PsEvColors.emerald)),
                                          if (booked.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Wrap(
                                                spacing: 4,
                                                runSpacing: 4,
                                                children: booked
                                                    .map((r) => Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                          decoration: BoxDecoration(color: PsEvColors.amberChip, borderRadius: BorderRadius.circular(999)),
                                                          child: Text(
                                                            'Booked ${timeFmt.format(r.start)}–${timeFmt.format(r.end)}',
                                                            style: const TextStyle(fontSize: 10, color: PsEvColors.amberChipText, fontWeight: FontWeight.w700),
                                                          ),
                                                        ))
                                                    .toList(),
                                              ),
                                            ),
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
                              );
                            }),
                        ],
                      ],
                    ],
                  ],
                ),
              );
            },
          ),
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 110,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 4,
              shadowColor: Colors.black26,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _recenterToMyLocation,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Icon(Icons.my_location, color: PsEvColors.emerald, size: 22),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 168,
            child: _quickAddButton(context),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: _buildFloatingFooter(context, app, auth, hasActiveBooking, notificationService),
          ),
        ],
      ),
    );
  }

  Widget _notificationBell(BuildContext context, NotificationService notificationService) {
    final count = notificationService.unreadCount;
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_outlined, size: 20, color: PsEvColors.slateText),
              if (count > 0)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: const BoxDecoration(color: PsEvColors.red, shape: BoxShape.circle),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAddButton(BuildContext context) {
    return Material(
      color: PsEvColors.emerald,
      shape: const CircleBorder(),
      elevation: 5,
      shadowColor: Colors.black45,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _showQuickAddSheet(context),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Icon(Icons.add, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildLiveSessionBanner(BuildContext context, Booking booking) {
    final inProgress = booking.status == BookingStatus.inProgress;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: booking.id))),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: inProgress ? PsEvColors.blue : PsEvColors.emerald,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              Icon(inProgress ? Icons.bolt : Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inProgress ? 'Charging at ${booking.chargerName}' : 'Confirmed at ${booking.chargerName}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      inProgress ? 'Tap to manage your session' : 'Tap to start when you plug in',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

 Widget _buildHostPendingBanner(BuildContext context, int count) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const MyBookingsScreen(
              showPastSessions: false,
              initialMode: BookingsViewMode.asHost,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: PsEvColors.amber,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              const Icon(Icons.pending_actions, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count booking request${count == 1 ? '' : 's'} waiting for your approval',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHostRunningBanner(BuildContext context, int count) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const MyBookingsScreen(
              showPastSessions: false,
              initialMode: BookingsViewMode.asHost,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: PsEvColors.blue,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count of your station${count == 1 ? '' : 's'} currently charging',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildFloatingFooter(BuildContext context, AppState app, AuthService auth, bool hasActiveBooking, NotificationService notificationService) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _collapseSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: PsEvColors.emerald, borderRadius: BorderRadius.circular(999)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('Map', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),

          _footerIconButton(
            icon: Icons.bolt,
            showBadge: hasActiveBooking,
            onTap: () async {
              final ok = await ensureRegistered(context);
              if (!ok || !context.mounted) return;
              // FIX (7/9 update, items #4/#9): always open My Bookings,
              // which now shows Upcoming/Active AND Past sections.
               Navigator.push(context, MaterialPageRoute(
                builder: (_) => const MyBookingsScreen(showPastSessions: false),
              ));

            },
          ),

          _footerIconButton(
            icon: Icons.account_balance_wallet_outlined,
            onTap: () async {
              final ok = await ensureRegistered(context);
              if (!ok || !context.mounted) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
            },
          ),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            // FIX (3/9 update, item #6 - "signing in lands on Profile
            // instead of Home"): previously this ALWAYS navigated to
            // ProfileScreen right after ensureRegistered() succeeded -
            // including for a brand-new guest who had just tapped this
            // icon purely to sign in/register. Now: only auto-navigate
            // to Profile if the user was ALREADY signed in before this
            // tap (i.e. they're intentionally opening their profile). A
            // fresh guest who just completed sign-in/registration simply
            // stays on the Home map afterward, exactly like completing a
            // sign-in from any OTHER quick-add action (Add a Car, Add a
            // Station, etc.) already did.
            onTap: () async {
              final wasAlreadyRegistered = auth.isRegistered;
              final ok = await ensureRegistered(context);
              if (!ok || !context.mounted) return;
              if (wasAlreadyRegistered) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: _footerProfileAvatar(auth, app.currentUserId, notificationService.unreadCount),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerProfileAvatar(AuthService auth, String? uid, int unreadCount) {
    if (uid == null) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: PsEvColors.slate200,
        child: const Text('?', style: TextStyle(color: PsEvColors.mutedText, fontSize: 11, fontWeight: FontWeight.w800)),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        StreamBuilder<Uint8List?>(
          stream: ProfilePhotoService.watch(uid),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            return CircleAvatar(
              radius: 16,
              backgroundColor: auth.isRegistered ? PsEvColors.emerald : PsEvColors.slate200,
              backgroundImage: bytes != null ? MemoryImage(bytes) : null,
              child: bytes == null
                  ? Text(
                      auth.isRegistered ? auth.initials : '?',
                      style: TextStyle(
                        color: auth.isRegistered ? Colors.white : PsEvColors.mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : null,
            );
          },
        ),
        if (unreadCount > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: PsEvColors.red, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 1.5))),
            ),
          ),
      ],
    );
  }

  Widget _footerIconButton({required IconData icon, required VoidCallback onTap, bool showBadge = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 24, color: PsEvColors.slateText),
            if (showBadge)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(color: PsEvColors.red, shape: BoxShape.circle),
                ),
              ),
          ],
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
