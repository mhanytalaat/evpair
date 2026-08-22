import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/availability_slot.dart';
import '../../models/charger_profile.dart';
import '../../models/enums.dart';
import '../../models/booking.dart';
import '../../services/booking_service.dart';
import '../../services/map_launcher_service.dart';
import '../../state/app_state.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import '../auth/register_screen.dart';
import 'charger_form_screen.dart';

/// Pushed screen: manage a single charger's FREE WINDOWS, its pending
/// booking requests, and an "Active Bookings" section (Booked vs
/// Charging). Since drivers can now book CUSTOM sub-ranges within a free
/// window, each window shows how many bookings currently fall within it.
///
/// IMPORTANT: every mutation to `ch.freeSlots` below is followed by a call
/// to `AppState.updateCharger(ch)` so the change is actually persisted to
/// Firestore. Without this, free windows only ever existed in memory and
/// silently disappeared the next time chargers were reloaded from
/// Firestore (e.g. after a sign-out/sign-in), and other users could never
/// see a window a host had just added.
class ManageChargerScreen extends StatefulWidget {
  final ChargerProfile charger;
  const ManageChargerScreen({super.key, required this.charger});

  @override
  State<ManageChargerScreen> createState() => _ManageChargerScreenState();
}

class _ManageChargerScreenState extends State<ManageChargerScreen> {
  final _uuid = const Uuid();
  Timer? _timer;
  bool _showAddSlotForm = false;
  bool _repeatWeekly = false;
  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;
  final Set<Weekday> _selectedWeekdays = {};
  DateTime? _repeatFrom;
  int _repeatWeeks = 4;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 60)));
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickRepeatFrom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 60)));
    if (picked != null) setState(() => _repeatFrom = picked);
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) setState(() => _end = picked);
  }

  void _resetForm() {
    _showAddSlotForm = false;
    _repeatWeekly = false;
    _date = null;
    _start = null;
    _end = null;
    _selectedWeekdays.clear();
    _repeatFrom = null;
    _repeatWeeks = 4;
  }

  void _addOneTimeSlot() {
    final ch = widget.charger;
    if (_date == null || _start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in date, start time, and end time.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    final start = DateTime(_date!.year, _date!.month, _date!.day, _start!.hour, _start!.minute);
    final end = DateTime(_date!.year, _date!.month, _date!.day, _end!.hour, _end!.minute);
    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    setState(() {
      ch.freeSlots.add(AvailabilitySlot(id: _uuid.v4(), chargerId: ch.chargerId, start: start, end: end));
      _resetForm();
    });
    // Persist to Firestore - without this the new window is lost as soon
    // as chargers are reloaded (e.g. sign-out/sign-in, or another user
    // opening the app), because it only ever existed on this in-memory
    // ChargerProfile instance.
    context.read<AppState>().updateCharger(ch);
  }

  void _addRecurringSlots() {
    final ch = widget.charger;
    if (_selectedWeekdays.isEmpty || _start == null || _end == null || _repeatFrom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick at least one weekday, a start date, and start/end times.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    if (!(_end!.hour * 60 + _end!.minute > _start!.hour * 60 + _start!.minute)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    final newSlots = <AvailabilitySlot>[];
    final totalDays = _repeatWeeks * 7;
    for (int i = 0; i < totalDays; i++) {
      final day = _repeatFrom!.add(Duration(days: i));
      final matches = _selectedWeekdays.any((w) => w.dartWeekday == day.weekday);
      if (!matches) continue;
      final start = DateTime(day.year, day.month, day.day, _start!.hour, _start!.minute);
      final end = DateTime(day.year, day.month, day.day, _end!.hour, _end!.minute);
      final weekdayEnum = Weekday.values.firstWhere((w) => w.dartWeekday == day.weekday);
      newSlots.add(AvailabilitySlot(
        id: _uuid.v4(),
        chargerId: ch.chargerId,
        start: start,
        end: end,
        recurrenceLabel: 'Every ${weekdayEnum.shortLabel}',
      ));
    }
    if (newSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching dates found in the selected range.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    setState(() {
      ch.freeSlots.addAll(newSlots);
      _resetForm();
    });
    // Persist the batch of recurring windows to Firestore - see note above.
    context.read<AppState>().updateCharger(ch);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${newSlots.length} recurring slot(s).'), backgroundColor: PsEvColors.emerald),
    );
  }

  Future<void> _openEdit() async {
    final ok = await ensureRegistered(context);
    if (!ok || !context.mounted) return;
    // ChargerFormScreen persists the edit (via AppState.updateCharger) on
    // save, so we just need to rebuild this screen with the updated data.
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChargerFormScreen(existing: widget.charger)));
    setState(() {});
  }

  Widget _weekdayChip(Weekday w) {
    final selected = _selectedWeekdays.contains(w);
    return ChoiceChip(
      label: Text(w.shortLabel),
      selected: selected,
      onSelected: (v) => setState(() => v ? _selectedWeekdays.add(w) : _selectedWeekdays.remove(w)),
      selectedColor: PsEvColors.emerald,
      labelStyle: TextStyle(color: selected ? Colors.white : PsEvColors.slateText, fontSize: 12, fontWeight: FontWeight.w600),
      backgroundColor: PsEvColors.slate100,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingService = context.watch<BookingService>();
    final ch = widget.charger;
    final dateFmt = DateFormat('EEE, MMM d • h:mm a');
    final slots = [...ch.freeSlots]..sort((a, b) => a.start.compareTo(b.start));
    final pending = bookingService.pendingApprovalsForHost(ch.hostId).where((b) => b.chargerId == ch.chargerId).toList();
    final confirmed = bookingService.confirmedForHost(ch.hostId).where((b) => b.chargerId == ch.chargerId).toList();
    final inProgress = bookingService.inProgressForHost(ch.hostId).where((b) => b.chargerId == ch.chargerId).toList();
    int bookingsWithinWindow(AvailabilitySlot s) => bookingService
        .filterByCategory('ongoing')
        .where((b) => b.chargerId == ch.chargerId && !b.requestedStart.isBefore(s.start) && !b.requestedEnd.isAfter(s.end))
        .length;
    return Scaffold(
      appBar: PsEvAppBar(title: ch.label),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ch.photoBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(ch.photoBytes!, height: 120, width: double.infinity, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 10),
                  Text(ch.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('${ch.city} • ${ch.area} • ${ch.powerKw} kW • ${ch.ampere}A • ${ch.connector.label} • ${ch.priceLabel}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                  if (ch.residentsOnly)
                    Padding(padding: const EdgeInsets.only(top: 6), child: PsEvTag.restricted(label: '${ch.restrictedCommunity} residents only')),
                  if (ch.mapLink != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: InkWell(
                        onTap: () => showMapAppChooser(
                          context,
                          latitude: ch.latitude,
                          longitude: ch.longitude,
                          label: ch.label,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on, size: 14, color: PsEvColors.emerald),
                            SizedBox(width: 4),
                            Text('Choose Maps App', style: TextStyle(color: PsEvColors.emerald, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  PsEvSoftButton(icon: Icons.edit_outlined, label: 'Edit Charger Details', onTap: _openEdit),
                ],
              ),
            ),
          ),
          if (confirmed.isNotEmpty || inProgress.isNotEmpty) ...[
            const Text('Active Bookings', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...confirmed.map((b) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _DriverAndCarInfo(booking: b),
                              Text('${dateFmt.format(b.requestedStart)} – ${DateFormat('h:mm a').format(b.requestedEnd)}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11)),
                            ],
                          ),
                        ),
                        PsEvStatusPill.bookedAwaitingScan(),
                      ],
                    ),
                  ),
                )),
            ...inProgress.map((b) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: _DriverAndCarInfo(booking: b),
                            ),
                            PsEvStatusPill.charging(),
                          ],
                        ),
                        if (b.sessionStartedAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _formatElapsed(DateTime.now().difference(b.sessionStartedAt!)),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: PsEvColors.blueChipText),
                            ),
                          ),
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: 8),
          ],
          const Text('Free Charging Windows', style: TextStyle(fontWeight: FontWeight.bold)),
          const Padding(
            padding: EdgeInsets.only(top: 2, bottom: 6),
            child: Text('Drivers can book any custom time range within each window below.', style: TextStyle(fontSize: 11, color: PsEvColors.mutedText)),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (slots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No windows added yet.', style: TextStyle(color: PsEvColors.mutedText)),
                    )
                  else
                    ...slots.map((s) {
                      final count = bookingsWithinWindow(s);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${dateFmt.format(s.start)} – ${DateFormat('h:mm a').format(s.end)}', style: const TextStyle(fontSize: 13)),
                                  if (s.recurrenceLabel != null)
                                    Text(s.recurrenceLabel!, style: const TextStyle(fontSize: 10, color: PsEvColors.emerald)),
                                ],
                              ),
                            ),
                            count > 0
                                ? PsEvStatusPill(label: '$count booking${count > 1 ? 's' : ''}', background: PsEvColors.emeraldChip, textColor: PsEvColors.emeraldChipText)
                                : PsEvStatusPill.free(),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: PsEvColors.red),
                              onPressed: () {
                                setState(() => ch.freeSlots.remove(s));
                                // Persist the removal - without this the
                                // deleted window would silently reappear
                                // next time chargers reload from Firestore.
                                context.read<AppState>().updateCharger(ch);
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  if (_showAddSlotForm)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: PsEvColors.slate100, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                Expanded(child: _modeButton('One-time', !_repeatWeekly, () => setState(() => _repeatWeekly = false))),
                                Expanded(child: _modeButton('Repeat weekly', _repeatWeekly, () => setState(() => _repeatWeekly = true))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (!_repeatWeekly) ...[
                            PsEvFilledButton(icon: Icons.calendar_today, label: _date == null ? 'Pick date' : DateFormat('MMM d').format(_date!), onTap: _pickDate),
                            const SizedBox(height: 8),
                            PsEvFilledButton(icon: Icons.schedule, label: _start == null ? 'Pick start time' : _start!.format(context), onTap: _pickStart),
                            const SizedBox(height: 8),
                            PsEvFilledButton(icon: Icons.schedule, label: _end == null ? 'Pick end time' : _end!.format(context), onTap: _pickEnd),
                          ] else ...[
                            const Align(alignment: Alignment.centerLeft, child: Text('Repeat on:', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText))),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 6, children: Weekday.values.map(_weekdayChip).toList()),
                            const SizedBox(height: 10),
                            PsEvFilledButton(icon: Icons.calendar_today, label: _repeatFrom == null ? 'Starting from...' : DateFormat('MMM d').format(_repeatFrom!), onTap: _pickRepeatFrom),
                            const SizedBox(height: 8),
                            PsEvFilledButton(icon: Icons.schedule, label: _start == null ? 'Pick start time' : _start!.format(context), onTap: _pickStart),
                            const SizedBox(height: 8),
                            PsEvFilledButton(icon: Icons.schedule, label: _end == null ? 'Pick end time' : _end!.format(context), onTap: _pickEnd),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Text('Repeat for:', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                                const SizedBox(width: 8),
                                DropdownButton<int>(
                                  value: _repeatWeeks,
                                  items: const [4, 8, 12].map((w) => DropdownMenuItem(value: w, child: Text('$w weeks'))).toList(),
                                  onChanged: (v) => setState(() => _repeatWeeks = v!),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: OutlinedButton(onPressed: () => setState(_resetForm), child: const Text('Cancel'))),
                              const SizedBox(width: 8),
                              Expanded(
                                child: PsEvFilledButton(
                                  label: _repeatWeekly ? 'Add Recurring Windows' : 'Add Window',
                                  onTap: _repeatWeekly ? _addRecurringSlots : _addOneTimeSlot,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: PsEvSoftButton(icon: Icons.add, label: '+ Add free window', onTap: () => setState(() => _showAddSlotForm = true)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Booking Requests', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (pending.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No pending booking requests.', style: TextStyle(color: PsEvColors.mutedText)),
            )
          else
            ...pending.map((b) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DriverAndCarInfo(booking: b),
                        Text('${dateFmt.format(b.requestedStart)} – ${DateFormat('h:mm a').format(b.requestedEnd)}', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12)),
                        Text('Held: ${b.heldAmount.toStringAsFixed(0)} EGP ✓', style: const TextStyle(fontSize: 12, color: PsEvColors.emerald)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: OutlinedButton(onPressed: () => bookingService.hostRespond(b.id, approve: false), child: const Text('Decline'))),
                            const SizedBox(width: 8),
                            Expanded(child: ElevatedButton(onPressed: () => bookingService.hostRespond(b.id, approve: true), child: const Text('Approve'))),
                          ],
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _modeButton(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? PsEvColors.emerald : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: active ? Colors.white : PsEvColors.slateText, fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }
}


class _DriverAndCarInfo extends StatelessWidget {
  final Booking booking;
  const _DriverAndCarInfo({required this.booking});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(booking.driverId).get(),
      builder: (context, snapshot) {
        var name = 'Driver'; String? phone;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          final first = data?['firstName'] as String? ?? '';
          final last = data?['lastName'] as String? ?? '';
          final fullName = [first, last].where((v) => v.trim().isNotEmpty).join(' ');
          if (fullName.isNotEmpty) name = fullName;
          phone = data?['phone'] as String?;
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Driver: $name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          if (phone != null && phone!.trim().isNotEmpty) Text('Mobile: $phone', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11)),
          Text('Car: ${booking.carBrand} ${booking.carModel}', style: const TextStyle(color: PsEvColors.slateText, fontSize: 12, fontWeight: FontWeight.w600)),
          Text('Plate: ${booking.carPlateNumber}', style: const TextStyle(color: PsEvColors.emerald, fontSize: 12, fontWeight: FontWeight.w800)),
          Text('${booking.carChargingStandard} • ${booking.carConnector} • ${booking.carMaxAmpere.toStringAsFixed(0)}A', style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11)),
        ]);
      },
    );
  }
}
