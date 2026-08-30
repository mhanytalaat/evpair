import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/car_brand_models.dart';

/// Loads the Brand -> [Models] map used on the Add/Edit Car form from a
/// Firestore `carModels` collection (one document per brand, doc ID = a
/// slug of the brand name, field `models` = array of strings) - so you
/// can add a new brand or a new model to an existing brand straight from
/// the Firebase console, with every driver's Add Car screen picking it
/// up immediately, no app rebuild/release required.
///
/// On the very FIRST run ever (the collection doesn't exist / is empty),
/// this seeds Firestore from the bundled `kSeedCarBrandModels` map in
/// data/car_brand_models.dart, so there's no manual data-entry step to
/// get started. Every later app start just reads whatever is currently
/// in Firestore.
///
/// Call `hydrate()` once during app startup (see main.dart), before
/// runApp - the same pattern already used for LocationsService and
/// PowerOptionsService.
class CarModelsService extends ChangeNotifier {
  CarModelsService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  bool isLoading = true;

  Future<void> hydrate() async {
    isLoading = true;
    notifyListeners();
    try {
      final snapshot = await _db.collection('carModels').get();
      if (snapshot.docs.isEmpty) {
        await _seedFromBundledMap();
        applyLiveCarBrandModels(kSeedCarBrandModels);
      } else {
        final brandModels = <String, List<String>>{};
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final brand = data['brand'] as String? ?? doc.id;
          // Guard against the exact same string-vs-number style mistake
          // seen with chargerPowerOptions: every item is coerced with
          // .toString() here, so even if the console saved a model name
          // oddly, this never throws and silently falls back to the old
          // list the way a strict `as String` cast would.
          final models = (data['models'] as List?)?.map((m) => m.toString()).toList() ?? const <String>[];
          if (models.isNotEmpty) brandModels[brand] = models;
        }
        applyLiveCarBrandModels(brandModels);
      }
    } catch (e) {
      debugPrint('CarModelsService.hydrate failed, falling back to the bundled map: $e');
      applyLiveCarBrandModels(kSeedCarBrandModels);
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> _seedFromBundledMap() async {
    final batch = _db.batch();
    for (final entry in kSeedCarBrandModels.entries) {
      final ref = _db.collection('carModels').doc(slugFor(entry.key));
      batch.set(ref, {
        'brand': entry.key,
        'models': entry.value,
      });
    }
    await batch.commit();
  }

  static String slugFor(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  /// Adds a new model to an existing (or brand-new) brand, live. Not
  /// wired to any UI yet - for now, add/edit directly in the Firebase
  /// console (carModels/{brandSlug} -> models array), or call this from
  /// a future admin screen.
  Future<void> addModelToBrand(String brand, String model) async {
    final ref = _db.collection('carModels').doc(slugFor(brand));
    await ref.set({
      'brand': brand,
      'models': FieldValue.arrayUnion([model]),
    }, SetOptions(merge: true));
    await hydrate();
  }
}
