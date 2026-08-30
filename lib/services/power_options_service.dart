import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/charger_power_options.dart';

/// Loads the list of selectable charger power (kW) values from a single
/// Firestore document at `appSettings/chargerPowerOptions` (field:
/// `values`, an array of numbers) - so you can add a new wattage (e.g.
/// 150 kW for a DC fast-charger) straight from the Firebase console,
/// with every host's "Add Charger" screen picking it up immediately, no
/// app rebuild/release required.
///
/// On the very FIRST run ever (the document doesn't exist), this seeds
/// Firestore from the bundled `kSeedPowerOptions` list in
/// data/charger_power_options.dart, so there's no manual data-entry step
/// to get started. Every later app start just reads whatever is
/// currently in Firestore.
///
/// Call `hydrate()` once during app startup (see main.dart), before
/// runApp - the same pattern already used for LocationsService,
/// AppState.hydrateFromFirestore(), and WalletService.hydrateFromFirestore().
class PowerOptionsService extends ChangeNotifier {
  PowerOptionsService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  static const _docPath = 'appSettings';
  static const _docId = 'chargerPowerOptions';

  bool isLoading = true;

  Future<void> hydrate() async {
    isLoading = true;
    notifyListeners();
    try {
      final doc = await _db.collection(_docPath).doc(_docId).get();
      if (!doc.exists || (doc.data()?['values'] as List?)?.isEmpty != false) {
        await _seedFromBundledList();
        applyLivePowerOptions(kSeedPowerOptions);
      } else {
        final raw = (doc.data()?['values'] as List).map((v) => (v as num).toDouble()).toList();
        applyLivePowerOptions(raw);
      }
    } catch (e) {
      debugPrint('PowerOptionsService.hydrate failed, falling back to the bundled list: $e');
      applyLivePowerOptions(kSeedPowerOptions);
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> _seedFromBundledList() async {
    await _db.collection(_docPath).doc(_docId).set({'values': kSeedPowerOptions});
  }

  /// Adds a new kW value live (e.g. from a future admin screen) and
  /// refreshes every screen currently reading kPowerOptions. Not wired
  /// to any UI yet - for now, add/edit values directly in the Firebase
  /// console (appSettings/chargerPowerOptions -> values array).
  Future<void> addPowerOption(double kw) async {
    await _db.collection(_docPath).doc(_docId).set({
      'values': FieldValue.arrayUnion([kw]),
    }, SetOptions(merge: true));
    await hydrate();
  }
}
