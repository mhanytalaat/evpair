import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../models/charger_profile.dart';
import '../../models/enums.dart';
import '../../services/pricing_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';

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
  late TextEditingController _nameCtrl;
  late TextEditingController _mapLinkCtrl;
  late TextEditingController _priceCtrl;
  late String _city;
  late String _area;
  late double _power;
  late double _ampere;
  late PricingModel _pricingModel;
  late bool _residentsOnly;
  late String _community;

  late ChargingStandard _chargingStandard;
  late ConnectorType _connector;

  Uint8List? _photoBytes;
  String? _priceError;

  bool get isEditing => widget.existing != null;

  late final String _pendingChargerId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _pendingChargerId = e?.chargerId ?? 'charger_${DateTime.now().millisecondsSinceEpoch}';

    _nameCtrl = TextEditingController(text: e?.label ?? 'My Home Charger');
    _mapLinkCtrl = TextEditingController(text: e?.mapLink ?? '');
    _priceCtrl = TextEditingController(text: e?.price.toString() ?? '');

    _city = e?.city ?? kCityOptions.first;
    final initialAreas = kCityAreaOptions[_city] ?? const ['Other'];
    _area = (e != null && initialAreas.contains(e.area)) ? e.area : initialAreas.first;

    _power = e?.powerKw ?? kPowerOptions[3];
    _ampere = e?.ampere ?? kAmpereOptions[1];
    _pricingModel = e?.pricingModel ?? PricingModel.perMinute;
    _residentsOnly = e?.residentsOnly ?? false;
    _community = e?.restrictedCommunity ?? kCommunityOptions.first;
    _photoBytes = e?.photoBytes;

    _chargingStandard = e?.chargingStandard ?? ChargingStandard.europeanCcs2;
    final validConnectors = _chargingStandard.compatibleConnectors;
    _connector = (e != null && validConnectors.contains(e.connector)) ? e.connector : validConnectors.first;
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

  ({double lat, double lng}) _resolveCoordinates() {
    final fromLink = tryParseLatLngFromMapLink(_mapLinkCtrl.text);
    if (fromLink != null) return fromLink;

    final areaCenter = kAreaCoordinates[_area];
    if (areaCenter != null) {
      final jitter = jitterOffsetFor(_pendingChargerId);
      return (lat: areaCenter.lat + jitter.lat, lng: areaCenter.lng + jitter.lng);
    }

    if (widget.existing != null) {
      return (lat: widget.existing!.latitude, lng: widget.existing!.longitude);
    }
    return kAreaCoordinates['Other']!;
  }

  void _submit() {
    final app = context.read<AppState>();
    final price = double.tryParse(_priceCtrl.text);
    if (_nameCtrl.text.trim().isEmpty || price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all charger details.'), backgroundColor: PsEvColors.red),
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

    final coords = _resolveCoordinates();

    if (isEditing) {
      final ch = widget.existing!;
      ch.label = _nameCtrl.text.trim();
      ch.city = _city;
      ch.area = _area;
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
      app.updateCharger(ch);
      Navigator.pop(context, true);
    } else {
      final charger = ChargerProfile(
        hostId: app.currentUserId ?? '',
        chargerId: _pendingChargerId,
        label: _nameCtrl.text.trim(),
        powerKw: _power,
        ampere: _ampere,
        connector: _connector,
        city: _city,
        area: _area,
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
      app.addCharger(charger);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final limits = PricingService.limitsFor(_pricingModel);
    final hint = PricingService.hintText(_pricingModel, _power, double.tryParse(_priceCtrl.text) ?? 0);
    final connectorsForStandard = _chargingStandard.compatibleConnectors;
    final areasForCity = kCityAreaOptions[_city] ?? const ['Other'];

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

                  const Text('City', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _city,
                    items: kCityOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() {
                      _city = v!;
                      final nextAreas = kCityAreaOptions[_city] ?? const ['Other'];
                      _area = nextAreas.first;
                    }),
                  ),
                  const SizedBox(height: 12),

                  const Text('Location / Area', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _area,
                    items: areasForCity.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                    onChanged: (v) => setState(() => _area = v!),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'City and Area are used for filtering/search. Without an exact Maps link, your '
                      'charger will be placed near the Area\'s center (spread out from other chargers in the '
                      'same area). For a precise pin at your exact address, paste a Maps link below.',
                      style: TextStyle(fontSize: 11, color: PsEvColors.mutedText),
                    ),
                  ),

                  const Text('Maps link', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  TextField(controller: _mapLinkCtrl, decoration: const InputDecoration(hintText: 'https://maps.google.com/?q=30.0131,31.4326')),
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
                    value: _power,
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

                  const SizedBox(height: 12),
                  PsEvFilledButton(
                    label: isEditing ? 'Save Changes' : 'Save Charger',
                    onTap: _submit,
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
