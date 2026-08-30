import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/egypt_locations.dart';

/// Item #2 of the 30/8 update: "countries and cities to be added on
/// Firestore". Loads governorates + their areas + their center
/// coordinates from a Firestore `governorates` collection (one document
/// per governorate, doc id = a slug of the name) instead of only the
/// bundled Dart constant - so an admin can add a new area/governorate
/// (or fix a typo) straight from the Firebase console with no app
/// release.
///
/// On the very FIRST run ever (the collection doesn't exist / is empty),
/// this seeds Firestore from the bundled `kSeedEgyptGovernorates` list in
/// data/egypt_locations.dart, so there's no manual data-entry step to get
/// started. Every later app start just reads whatever is currently in
/// Firestore.
///
/// Call `hydrate()` once during app startup (see main.dart), before
/// runApp - the exact same pattern already used for
/// AppState.hydrateFromFirestore() and WalletService.hydrateFromFirestore().
class LocationsService extends ChangeNotifier {
  LocationsService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  bool isLoading = true;

  Future<void> hydrate() async {
    isLoading = true;
    notifyListeners();
    try {
      final snapshot = await _db.collection('governorates').get();
      if (snapshot.docs.isEmpty) {
        await _seedFromBundledList();
        applyLiveGovernorates(kSeedEgyptGovernorates, kSeedGovernorateCoordinates);
      } else {
        final governorates = <EgyptGovernorate>[];
        final coordinates = <String, ({double lat, double lng})>{};
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final name = data['name'] as String? ?? doc.id;
          final areas = (data['areas'] as List?)?.map((a) => a.toString()).toList() ?? const <String>[];
          final isPriority = data['isPriority'] as bool? ?? false;
          governorates.add(EgyptGovernorate(name: name, areas: areas, isPriority: isPriority));
          final lat = (data['lat'] as num?)?.toDouble();
          final lng = (data['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            coordinates[name] = (lat: lat, lng: lng);
          }
        }
        // Keep the same ordering convention as the original bundled list:
        // priority governorates (Cairo/Giza/North Coast) first, then the
        // rest alphabetically.
        governorates.sort((a, b) {
          if (a.isPriority != b.isPriority) return a.isPriority ? -1 : 1;
          return a.name.compareTo(b.name);
        });
        applyLiveGovernorates(governorates, coordinates);
      }
    } catch (e) {
      debugPrint('LocationsService.hydrate failed, falling back to the bundled list: $e');
      applyLiveGovernorates(kSeedEgyptGovernorates, kSeedGovernorateCoordinates);
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> _seedFromBundledList() async {
    final batch = _db.batch();
    for (final g in kSeedEgyptGovernorates) {
      final coords = kSeedGovernorateCoordinates[g.name];
      final ref = _db.collection('governorates').doc(slugFor(g.name));
      batch.set(ref, {
        'name': g.name,
        'areas': g.areas,
        'isPriority': g.isPriority,
        if (coords != null) 'lat': coords.lat,
        if (coords != null) 'lng': coords.lng,
      });
    }
    await batch.commit();
  }

  static String slugFor(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  /// Lets the "Can't find your area?" flow (see LocationPickerField,
  /// which currently only writes to `locationRequests` for manual admin
  /// review) be upgraded later to add the area live and refresh
  /// everyone's picker immediately, without waiting for an app release.
  /// Not wired to any UI yet - call this from an admin screen when
  /// approving a location request.
  Future<void> addAreaToGovernorate(String governorateName, String area) async {
    final ref = _db.collection('governorates').doc(slugFor(governorateName));
    await ref.set({
      'name': governorateName,
      'areas': FieldValue.arrayUnion([area]),
    }, SetOptions(merge: true));
    await hydrate();
  }
}
