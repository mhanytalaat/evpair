import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../data/egypt_locations.dart';
import '../../theme/ps_ev_theme.dart';

/// Cascading City/Governorate -> Area picker backed by the curated
/// EgyptGovernorate list, used both by the driver Home filter and the
/// Home Installation & Equipment service request form, so location
/// values are always spelled identically everywhere in the app.
///
/// Includes a "Can't find your area?" link that lets the user submit a
/// free-text location request straight to the `locationRequests`
/// Firestore collection - the app doesn't try to guess or auto-add it,
/// an admin reviews these manually and can add the area to
/// egypt_locations.dart in a future update if it's a good fit.
class LocationPickerField extends StatelessWidget {
  final String? governorate;
  final String? area;
  final ValueChanged<String?> onGovernorateChanged;
  final ValueChanged<String?> onAreaChanged;
  final String userId;
  final String userName;

  /// Set true for filter usage (adds "All Cities"/"All Areas" options).
  /// Set false for a required field in a submission form (no "All").
  final bool showAllOption;

  const LocationPickerField({
    super.key,
    required this.governorate,
    required this.area,
    required this.onGovernorateChanged,
    required this.onAreaChanged,
    required this.userId,
    required this.userName,
    this.showAllOption = false,
  });

  @override
  Widget build(BuildContext context) {
    // Defensive: never pass a value into DropdownButtonFormField that
    // isn't actually present in its items list (Flutter throws an
    // assertion error in that case) - e.g. if a previously saved
    // governorate/area no longer exists in the curated list.
    final safeGovernorate = isKnownGovernorate(governorate) ? governorate : null;
    final safeArea = isKnownArea(safeGovernorate, area) ? area : null;
    final areas = areasFor(safeGovernorate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          value: safeGovernorate,
          decoration: const InputDecoration(labelText: 'City / Governorate'),
          isExpanded: true,
          items: [
            if (showAllOption) const DropdownMenuItem<String?>(value: null, child: Text('All Cities')),
            ...kEgyptGovernorates.map(
              (g) => DropdownMenuItem<String?>(value: g.name, child: Text(g.name, overflow: TextOverflow.ellipsis)),
            ),
          ],
          onChanged: (v) {
            onGovernorateChanged(v);
            onAreaChanged(null);
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          value: safeArea,
          decoration: const InputDecoration(labelText: 'Area / Compound'),
          isExpanded: true,
          items: [
            if (showAllOption) const DropdownMenuItem<String?>(value: null, child: Text('All Areas')),
            ...areas.map((a) => DropdownMenuItem<String?>(value: a, child: Text(a, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: safeGovernorate == null && !showAllOption ? null : onAreaChanged,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _showRequestNewLocationDialog(context),
            icon: const Icon(Icons.add_location_alt_outlined, size: 15),
            label: const Text("Can't find your area?", style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Future<void> _showRequestNewLocationDialog(BuildContext context) async {
    final cityCtrl = TextEditingController(text: governorate ?? '');
    final areaCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request a New Location'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Let us know your city and area and our team will consider adding it.",
                style: TextStyle(fontSize: 12, color: PsEvColors.mutedText),
              ),
              const SizedBox(height: 12),
              TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'City / Governorate')),
              const SizedBox(height: 8),
              TextField(controller: areaCtrl, decoration: const InputDecoration(labelText: 'Area / Compound')),
              const SizedBox(height: 8),
              TextField(controller: notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );

    if (submitted != true) return;
    if (cityCtrl.text.trim().isEmpty && areaCtrl.text.trim().isEmpty) return;

    await FirebaseFirestore.instance.collection('locationRequests').add({
      'userId': userId,
      'userName': userName,
      'requestedCity': cityCtrl.text.trim(),
      'requestedArea': areaCtrl.text.trim(),
      'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Thanks! We've sent your location request to our team.")),
    );
  }
}
