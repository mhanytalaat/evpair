import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../state/app_state.dart';
import '../../models/charger_profile.dart';
import '../../models/availability_slot.dart';
import '../../models/enums.dart';
import '../../services/auth_service.dart';
import '../../services/pricing_service.dart';
import '../../data/egypt_locations.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';
import '../shared/location_picker_field.dart';
import 'pick_location_on_map_screen.dart';

({double lat, double lng})? tryParseLatLngFromMapLink(String? link) {
  if (link == null || link.trim().isEmpty) return null;
  final match = RegExp(r'(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)').firstMatch(link);
  if (match == null) return null;
  final lat = double.tryParse(match.group(1)!);
  final lng = double.tryParse(match.group(2)!);
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return (lat: lat, lng: lng);
}

class ChargerFormScreen extends StatefulWidget {
  final ChargerProfile? existing;
  const ChargerFormScreen({super.key, this.existing});
  @override
  State<ChargerFormScreen> createState() => _ChargerFormScreenState();
}

class _ChargerFormScreenState extends State<ChargerFormScreen> {
  final _uuid = const Uuid();
  late TextEditingController _nameCtrl;
  late TextEditingController _mapLinkCtrl;
  late TextEditingController _priceCtrl;
  String? _city;
  String? _area;
  late double _power;
  late double _ampere;
  late PricingModel _pricingModel;
  late bool _residentsOnly;
  late String _community;
  late ChargingStandard _chargingStandard;
  late ConnectorType _connector;
  Uint8List? _photoBytes;
  String? _priceError;
  bool _submitting = false;
  bool get isEditing => widget.existing != null;
  late final String _pendingChargerId;

  double? _pickedLat;
  double? _pickedLng;

  final List<AvailabilitySlot> _pendingSlots = [];
  bool _showAddSlotForm = false;
  bool _repeatWeekly = false;
  DateTime? _slotDate;
  TimeOfDay? _slotStart;
  TimeOfDay? _slotEnd;
  final Set<Weekday> _selectedWeekdays = {};
  DateTime? _repeatFrom;
  int _repeatWeeks = 4;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _pendingChargerId = e?.chargerId ?? 'charger_${DateTime.now().millisecondsSinceEpoch}';
    _nameCtrl = TextEditingController(text: e?.label ?? 'My Home Charger');
    _mapLinkCtrl = TextEditingController(text: e?.mapLink ?? '');
    _priceCtrl = TextEditingController(text: e?.price.toString() ?? '');
    _city = (e != null && isKnownGovernorate(e.city)) ? e.city : null;
    _area = (e != null && isKnownArea(_city, e.area)) ? e.area : null;
    _power = (e != null && kPowerOptions.contains(e.powerKw)) ? e.powerKw : kPowerOptions.first;
    _ampere = e?.ampere ?? kAmpereOptions[1];
    _pricingModel = e?.pricingModel ?? PricingModel.perMinute;
    _residentsOnly = e?.residentsOnly ?? false;
    _community = e?.restrictedCommunity ?? kCommunityOptions.first;
    _photoBytes = e?.photoBytes;
    _chargingStandard = e?.chargingStandard ?? ChargingStandard.europeanCcs2;
    final validConnectors = _chargingStandard.compatibleConnectors;
    _connector = (e != null && validConnectors.contains(e.connector)) ? e.connector : validConnectors.first;
    if (e != null) {
      _pickedLat = e.latitude;
      _pickedLng = e.longitude;
    }
  }

  Future<void> _pickPhoto() async {
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
              title: const Text('Choose from Gallery'),
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
      if (mounted) setState(() => _photoBytes = bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load that image: $e'), backgroundColor: PsEvColors.red),
        );
      }
    }
  }

  void _validatePriceLive(String value) {
    final price = double.tryParse(value);
    final limits = PricingService.limitsFor(_pricingModel);
    setState(() {
      if (price == null) {
        _priceError = null;
      } else if (price < limits.min || price > limits.max) {
        _priceError = 'Must be ${limits.min}–${limits.max} ${limits.unitLabel}';
      } else {
        _priceError = null;
      }
    });
  }

  Future<void> _openMapPicker() async {
    final start = (_pickedLat != null && _pickedLng != null)
        ? (lat: _pickedLat!, lng: _pickedLng!)
        : (kGovernorateCoordinates[_city] ?? kGovernorateCoordinates['Cairo']!);
    final result = await Navigator.push<({double lat, double lng})>(
      context,
      MaterialPageRoute(
        builder: (_) => PickLocationOnMapScreen(initialLat: start.lat, initialLng: start.lng),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _pickedLat = result.lat;
        _pickedLng = result.lng;
      });
    }
  }

  ({double lat, double lng}) _resolveCoordinates() {
    if (_pickedLat != null && _pickedLng != null) {
      return (lat: _pickedLat!, lng: _pickedLng!);
    }
    final fromLink = tryParseLatLngFromMapLink(_mapLinkCtrl.text);
    if (fromLink != null) return fromLink;
    final govCenter = kGovernorateCoordinates[_city];
    if (govCenter != null) {
      final jitter = jitterOffsetFor(_pendingChargerId);
      return (lat: govCenter.lat + jitter.lat, lng: govCenter.lng + jitter.lng);
    }
    if (widget.existing != null) {
      return (lat: widget.existing!.latitude, lng: widget.existing!.longitude);
    }
    return kGovernorateCoordinates['Cairo']!;
  }

  Future<void> _pickSlotDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 60)));
    if (picked != null) setState(() => _slotDate = picked);
  }

  Future<void> _pickRepeatFrom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 60)));
    if (picked != null) setState(() => _repeatFrom = picked);
  }

  Future<void> _pickSlotStart() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) setState(() => _slotStart = picked);
  }

  Future<void> _pickSlotEnd() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) setState(() => _slotEnd = picked);
  }

  void _resetSlotForm() {
    _showAddSlotForm = false;
    _repeatWeekly = false;
    _slotDate = null;
    _slotStart = null;
    _slotEnd = null;
    _selectedWeekdays.clear();
    _repeatFrom = null;
    _repeatWeeks = 4;
  }

  void _addOneTimeSlotPending() {
    if (_slotDate == null || _slotStart == null || _slotEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in date, start time, and end time.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    final start = DateTime(_slotDate!.year, _slotDate!.month, _slotDate!.day, _slotStart!.hour, _slotStart!.minute);
    final end = DateTime(_slotDate!.year, _slotDate!.month, _slotDate!.day, _slotEnd!.hour, _slotEnd!.minute);
    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    setState(() {
      // NOTE: recurrenceLabel intentionally left null here for a
      // one-time slot - ChargerProfile.toFirestore()'s _slotToFirestore
      // helper now OMITS this key entirely from the Firestore map
      // instead of sending it as a null value, which is the fix for
      // "one-time slot doesn't save, recurring does" (see
      // models/charger_profile.dart).
      _pendingSlots.add(AvailabilitySlot(id: _uuid.v4(), chargerId: _pendingChargerId, start: start, end: end));
      _resetSlotForm();
    });
  }

  void _addRecurringSlotsPending() {
    if (_selectedWeekdays.isEmpty || _slotStart == null || _slotEnd == null || _repeatFrom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick at least one weekday, a start date, and start/end times.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    if (!(_slotEnd!.hour * 60 + _slotEnd!.minute > _slotStart!.hour * 60 + _slotStart!.minute)) {
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
      final start = DateTime(day.year, day.month, day.day, _slotStart!.hour, _slotStart!.minute);
      final end = DateTime(day.year, day.month, day.day, _slotEnd!.hour, _slotEnd!.minute);
      final weekdayEnum = Weekday.values.firstWhere((w) => w.dartWeekday == day.weekday);
      newSlots.add(AvailabilitySlot(
        id: _uuid.v4(),
        chargerId: _pendingChargerId,
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
      _pendingSlots.addAll(newSlots);
      _resetSlotForm();
    });
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

  /// FIX: now `async` and AWAITS the Firestore write inside a
  /// try/catch. Previously this fired `app.addCharger(...)`/
  /// `app.updateCharger(...)` without awaiting, so a failed write was
  /// never detected - the screen just closed as if it succeeded, and
  /// the charger later vanished once the real-time listener resynced
  /// from the server. Now:
  ///   - On SUCCESS: pops with 'added'/'updated' exactly as before.
  ///   - On FAILURE: stays open, resets the Saving state, and shows the
  ///     ACTUAL error message in a red SnackBar so it's visible instead
  ///     of silently disappearing.
  Future<void> _submit() async {
    final app = context.read<AppState>();
    final price = double.tryParse(_priceCtrl.text);
    if (_nameCtrl.text.trim().isEmpty || price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all charger details.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    if (_city == null || _area == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select the City and Area for this charger.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    if (!PricingService.isPriceValid(_pricingModel, price)) {
      final l = PricingService.limitsFor(_pricingModel);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Price must be between ${l.min} and ${l.max} ${l.unitLabel} — please enter a realistic value.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    if (_residentsOnly && _community.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select which compound/community this charger is restricted to.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    if (!isEditing && _pendingSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one free charging window before saving.'), backgroundColor: PsEvColors.red),
      );
      return;
    }
    final coords = _resolveCoordinates();
    setState(() => _submitting = true);
    try {
      if (isEditing) {
        final ch = widget.existing!;
        ch.label = _nameCtrl.text.trim();
        ch.city = _city!;
        ch.area = _area!;
        ch.mapLink = _mapLinkCtrl.text.trim().isEmpty ? null : _mapLinkCtrl.text.trim();
        ch.connector = _connector;
        ch.powerKw = _power;
        ch.ampere = _ampere;
        ch.pricingModel = _pricingModel;
        ch.price = price;
        ch.photoBytes = _photoBytes ?? ch.photoBytes;
        ch.residentsOnly = _residentsOnly;
        ch.restrictedCommunity = _residentsOnly ? _community : null;
        ch.chargingStandard = _chargingStandard;
        ch.latitude = coords.lat;
        ch.longitude = coords.lng;
        await app.updateCharger(ch);
        if (!mounted) return;
        Navigator.pop(context, 'updated');
      } else {
        final charger = ChargerProfile(
          hostId: app.currentUserId ?? '',
          chargerId: _pendingChargerId,
          label: _nameCtrl.text.trim(),
          powerKw: _power,
          ampere: _ampere,
          connector: _connector,
          city: _city!,
          area: _area!,
          chargingStandard: _chargingStandard,
          pricingModel: _pricingModel,
          price: price,
          latitude: coords.lat,
          longitude: coords.lng,
          photoBytes: _photoBytes,
          mapLink: _mapLinkCtrl.text.trim().isEmpty ? null : _mapLinkCtrl.text.trim(),
          residentsOnly: _residentsOnly,
          restrictedCommunity: _residentsOnly ? _community : null,
        );
        charger.freeSlots.addAll(_pendingSlots);
        await app.addCharger(charger);
        if (!mounted) return;
        Navigator.pop(context, 'added');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save this charger: $e'),
          backgroundColor: PsEvColors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final app = context.read<AppState>();
    final limits = PricingService.limitsFor(_pricingModel);
    final hint = PricingService.hintText(_pricingModel, _power, double.tryParse(_priceCtrl.text) ?? 0);
    final connectorsForStandard = _chargingStandard.compatibleConnectors;
    final hasPickedPin = _pickedLat != null && _pickedLng != null;
    final dateFmt = DateFormat('EEE, MMM d');
    final timeFmt = DateFormat('h:mm a');
    return Scaffold(
      appBar: PsEvAppBar(title: isEditing ? 'Edit Charger' : 'Add Charger'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Station photo', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 6),
                  if (_photoBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_photoBytes!, height: 130, width: double.infinity, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _pickPhoto,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: PsEvColors.slate200, width: 2),
                        borderRadius: BorderRadius.circular(14),
                        color: PsEvColors.slate100.withOpacity(0.5),
                      ),
                      child: Text(
                        _photoBytes == null ? '📷 Add station photo (Camera or Gallery)' : '📷 Change photo (Camera or Gallery)',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Charger name', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  TextField(controller: _nameCtrl),
                  const SizedBox(height: 12),
                  const Text('City & Area', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  LocationPickerField(
                    governorate: _city,
                    area: _area,
                    showAllOption: false,
                    userId: app.currentUserId ?? '',
                    userName: auth.displayName,
                    onGovernorateChanged: (v) => setState(() {
                      _city = v;
                      _area = null;
                    }),
                    onAreaChanged: (v) => setState(() => _area = v),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'City and Area are used for filtering/search, and must match the same list drivers '
                      'use. For a precise pin at your exact address, use "Pick Exact Location on Map" below - '
                      "it's more reliable than a pasted Maps link, which often doesn't contain exact coordinates.",
                      style: TextStyle(fontSize: 11, color: PsEvColors.mutedText),
                    ),
                  ),
                  PsEvSoftButton(
                    icon: Icons.pin_drop_outlined,
                    label: hasPickedPin ? 'Change Pin Location' : 'Pick Exact Location on Map',
                    onTap: _openMapPicker,
                  ),
                  if (hasPickedPin)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 14, color: PsEvColors.emerald),
                          const SizedBox(width: 4),
                          Text(
                            'Custom pin set (${_pickedLat!.toStringAsFixed(5)}, ${_pickedLng!.toStringAsFixed(5)})',
                            style: const TextStyle(fontSize: 11, color: PsEvColors.emerald, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text('Maps link (optional)', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  TextField(controller: _mapLinkCtrl, decoration: const InputDecoration(hintText: 'https://maps.google.com/?q=30.0131,31.4326')),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                      'Only used if you have NOT picked a pin above. Note: many shortened Google Maps links '
                      "(maps.app.goo.gl/...) don't contain usable coordinates - the map picker above is more reliable.",
                      style: TextStyle(fontSize: 11, color: PsEvColors.mutedText),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Charging standard', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<ChargingStandard>(
                    value: _chargingStandard,
                    items: ChargingStandard.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
                    onChanged: (v) => setState(() {
                      _chargingStandard = v!;
                      _connector = _chargingStandard.compatibleConnectors.first;
                    }),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 8),
                    child: Text(
                      'Select the standard this physical station is actually wired for. Type 2 and CCS2 only '
                      'ever belong to the European/International standard; Chinese GB/T stations use entirely '
                      'different, incompatible AC/DC connectors.',
                      style: TextStyle(fontSize: 11, color: PsEvColors.mutedText),
                    ),
                  ),
                  const Text('Connector type', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<ConnectorType>(
                    value: _connector,
                    items: connectorsForStandard.map((c) => DropdownMenuItem(value: c, child: Text(c.label))).toList(),
                    onChanged: (v) => setState(() => _connector = v!),
                  ),
                  const SizedBox(height: 12),
                  const Text('Power (kW)', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<double>(
                    value: kPowerOptions.contains(_power) ? _power : kPowerOptions.first,
                    items: kPowerOptions.map((p) => DropdownMenuItem(value: p, child: Text('$p kW'))).toList(),
                    onChanged: (v) => setState(() => _power = v!),
                  ),
                  const SizedBox(height: 12),
                  const Text('Ampere (A)', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<double>(
                    value: _ampere,
                    items: kAmpereOptions.map((a) => DropdownMenuItem(value: a, child: Text('${a.toStringAsFixed(0)} A'))).toList(),
                    onChanged: (v) => setState(() => _ampere = v!),
                  ),
                  const SizedBox(height: 12),
                  const Text('Pricing model', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<PricingModel>(
                    value: _pricingModel,
                    items: const [
                      DropdownMenuItem(value: PricingModel.perMinute, child: Text('Per Minute (time-based)')),
                      DropdownMenuItem(value: PricingModel.perKwh, child: Text('Per kWh (energy-based)')),
                    ],
                    onChanged: (v) => setState(() {
                      _pricingModel = v!;
                      _validatePriceLive(_priceCtrl.text);
                    }),
                  ),
                  const SizedBox(height: 12),
                  Text('Price (${limits.unitLabel})', style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: _validatePriceLive,
                    decoration: InputDecoration(errorText: _priceError),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 10),
                    child: Text(hint, style: const TextStyle(fontSize: 11, color: PsEvColors.emerald)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: PsEvColors.emerald,
                    title: const Text('Restrict to my compound/community residents only', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                      'Only drivers who selected the same community in their Car Profile will be able to see and book this charger.',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _residentsOnly,
                    onChanged: (v) => setState(() => _residentsOnly = v),
                  ),
                  if (_residentsOnly)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      child: DropdownButtonFormField<String>(
                        value: _community,
                        decoration: const InputDecoration(labelText: 'Which compound/community?'),
                        items: kCommunityOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (v) => setState(() => _community = v!),
                      ),
                    ),
                  if (!isEditing) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Text('Free Charging Windows', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(width: 6),
                        const Text('*', style: TextStyle(color: PsEvColors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 2, bottom: 8),
                      child: Text(
                        'Add at least one window when drivers can book this charger. You can add more, or edit '
                        'and delete these, at any time afterwards from Manage Charger.',
                        style: TextStyle(fontSize: 11, color: PsEvColors.mutedText),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: PsEvColors.slate100, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          if (_pendingSlots.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                'No windows added yet - add at least one below.',
                                style: TextStyle(color: PsEvColors.red, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            )
                          else
                            ..._pendingSlots.map((s) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${dateFmt.format(s.start)} • ${timeFmt.format(s.start)} – ${timeFmt.format(s.end)}', style: const TextStyle(fontSize: 13)),
                                            if (s.recurrenceLabel != null)
                                              Text(s.recurrenceLabel!, style: const TextStyle(fontSize: 10, color: PsEvColors.emerald)),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: PsEvColors.red),
                                        onPressed: () => setState(() => _pendingSlots.remove(s)),
                                      ),
                                    ],
                                  ),
                                )),
                          if (_showAddSlotForm)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(color: PsEvColors.slate100, borderRadius: BorderRadius.circular(12)),
                                    child: Row(
                                      children: [
                                        Expanded(child: _modeButton('One-time', !_repeatWeekly, () => setState(() => _repeatWeekly = false))),
                                        Expanded(child: _modeButton('Repeat weekly', _repeatWeekly, () => setState(() => _repeatWeekly = true))),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (!_repeatWeekly) ...[
                                    PsEvFilledButton(icon: Icons.calendar_today, label: _slotDate == null ? 'Pick date' : DateFormat('MMM d').format(_slotDate!), onTap: _pickSlotDate),
                                    const SizedBox(height: 8),
                                    PsEvFilledButton(icon: Icons.schedule, label: _slotStart == null ? 'Pick start time' : _slotStart!.format(context), onTap: _pickSlotStart),
                                    const SizedBox(height: 8),
                                    PsEvFilledButton(icon: Icons.schedule, label: _slotEnd == null ? 'Pick end time' : _slotEnd!.format(context), onTap: _pickSlotEnd),
                                  ] else ...[
                                    const Align(alignment: Alignment.centerLeft, child: Text('Repeat on:', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText))),
                                    const SizedBox(height: 6),
                                    Wrap(spacing: 6, runSpacing: 6, children: Weekday.values.map(_weekdayChip).toList()),
                                    const SizedBox(height: 10),
                                    PsEvFilledButton(icon: Icons.calendar_today, label: _repeatFrom == null ? 'Starting from...' : DateFormat('MMM d').format(_repeatFrom!), onTap: _pickRepeatFrom),
                                    const SizedBox(height: 8),
                                    PsEvFilledButton(icon: Icons.schedule, label: _slotStart == null ? 'Pick start time' : _slotStart!.format(context), onTap: _pickSlotStart),
                                    const SizedBox(height: 8),
                                    PsEvFilledButton(icon: Icons.schedule, label: _slotEnd == null ? 'Pick end time' : _slotEnd!.format(context), onTap: _pickSlotEnd),
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
                                      Expanded(child: OutlinedButton(onPressed: () => setState(_resetSlotForm), child: const Text('Cancel'))),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: PsEvFilledButton(
                                          label: _repeatWeekly ? 'Add Recurring Windows' : 'Add Window',
                                          onTap: _repeatWeekly ? _addRecurringSlotsPending : _addOneTimeSlotPending,
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
                  ],
                  const SizedBox(height: 16),
                  PsEvFilledButton(
                    label: _submitting ? 'Saving...' : (isEditing ? 'Save Changes' : 'Save Charger'),
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
