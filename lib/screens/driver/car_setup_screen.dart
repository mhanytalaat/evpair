import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../models/car_profile.dart';
import '../../models/enums.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';

/// Add/Edit form for a SINGLE car. Reached from MyCarsScreen - either with
/// `existing == null` (add a new car to the driver's list) or with an
/// existing car to edit in place. This is the same Add/Edit-in-one-form
/// pattern already used for chargers (see host/charger_form_screen.dart).
class CarSetupScreen extends StatefulWidget {
  final CarProfile? existing;
  const CarSetupScreen({super.key, this.existing});

  @override
  State<CarSetupScreen> createState() => _CarSetupScreenState();
}

class _CarSetupScreenState extends State<CarSetupScreen> {
  late TextEditingController _rangeCtrl;
  late double _ampere;
  late String _community;

  // Cascading Brand -> Model selection.
  late String _brand;
  late String _model;

  // Charging standard is set FIRST; Connector Type cascades from it (only
  // connectors valid for the chosen standard are selectable).
  late ChargingStandard _chargingStandard;
  late ConnectorType _connector;

  bool get isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    _brand = (e != null && kCarBrandModels.containsKey(e.brand)) ? e.brand : kCarBrandModels.keys.first;
    _model = (e != null && kCarBrandModels[_brand]!.contains(e.model)) ? e.model : kCarBrandModels[_brand]!.first;

    _rangeCtrl = TextEditingController(text: e?.rangeKm.toStringAsFixed(0) ?? '450');
    _ampere = e?.maxAmpere ?? 32;
    _community = e?.community ?? kCommunityOptions.first;

    _chargingStandard = e?.chargingStandard ?? ChargingStandard.europeanCcs2;
    final validConnectors = _chargingStandard.compatibleConnectors;
    _connector = (e != null && validConnectors.contains(e.connector)) ? e.connector : validConnectors.first;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final modelsForBrand = kCarBrandModels[_brand]!;
    final connectorsForStandard = _chargingStandard.compatibleConnectors;

    return Scaffold(
      appBar: PsEvAppBar(title: isEditing ? 'Edit Car' : 'Add Car'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Car brand', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _brand,
                    items: kCarBrandModels.keys.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                    onChanged: (v) => setState(() {
                      _brand = v!;
                      _model = kCarBrandModels[_brand]!.first;
                    }),
                  ),
                  const SizedBox(height: 12),

                  const Text('Car model', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _model,
                    items: modelsForBrand.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (v) => setState(() => _model = v!),
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
                    padding: EdgeInsets.only(top: 6, bottom: 12),
                    child: Text(
                      'Chinese-market/imported EVs (e.g. Arcfox, many BYD imports) use GB/T. '
                      'European-market EVs (e.g. VW, most Geely-for-Europe models) use CCS2/Type 2. '
                      'These are physically different, incompatible connector families.',
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

                  const Text('Max ampere (A)', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<double>(
                    value: _ampere,
                    items: kAmpereOptions.map((a) => DropdownMenuItem(value: a, child: Text('${a.toStringAsFixed(0)} A'))).toList(),
                    onChanged: (v) => setState(() => _ampere = v!),
                  ),
                  const SizedBox(height: 12),

                  const Text('Full-charge range (km)', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  TextField(controller: _rangeCtrl, keyboardType: TextInputType.number),
                  const SizedBox(height: 12),

                  const Text('My compound / community', style: TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _community,
                    items: kCommunityOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() => _community = v!),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Used to unlock residents-only chargers in your compound.', style: TextStyle(fontSize: 11, color: PsEvColors.emerald)),
                  ),
                  const SizedBox(height: 12),

                  PsEvFilledButton(
                    label: isEditing ? 'Save Changes' : 'Save Car',
                    onTap: () {
                      final car = CarProfile(
                        // Reuse the same carId when editing so this
                        // updates the existing car in place rather than
                        // creating a duplicate; generate a fresh id (based
                        // on creation time) only when adding a new one.
                        carId: widget.existing?.carId ?? 'car_${DateTime.now().millisecondsSinceEpoch}',
                        driverId: kCurrentUserId,
                        brand: _brand,
                        model: _model,
                        maxAmpere: _ampere,
                        rangeKm: double.tryParse(_rangeCtrl.text) ?? 450,
                        connector: _connector,
                        chargingStandard: _chargingStandard,
                        community: _community,
                      );
                      if (isEditing) {
                        app.updateCar(car);
                      } else {
                        app.addCar(car);
                      }
                      Navigator.pop(context);
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
