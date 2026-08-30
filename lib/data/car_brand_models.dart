/// Car brand/model options offered on the Add/Edit Car form (see
/// screens/driver/car_setup_screen.dart).
///
/// Same live-data pattern already used for kW options and Egypt
/// governorates: this file still ships a bundled SEED map
/// (`kSeedCarBrandModels`) so the app always has values even before any
/// network call completes. The value actually shown in the app is the
/// LIVE map (`kCarBrandModels`), which starts out equal to the seed map
/// but gets replaced with whatever is in the Firestore `carModels`
/// collection once `CarModelsService.hydrate()` runs (see
/// services/car_models_service.dart and the call added in main.dart).
///
/// On the very first run ever (empty collection), CarModelsService seeds
/// Firestore FROM this map, so no manual data entry is needed to get
/// started - after that, editing a brand's `models` array (or adding a
/// new brand document) in the Firebase console updates every driver's
/// Add Car dropdown with no app release.
const Map<String, List<String>> kSeedCarBrandModels = {
  'Arcfox': ['T1', 'Alpha S', 'Alpha T'],
  'BYD': ['Atto 3', 'Dolphin', 'Seal', 'Han', 'Tang', 'Song Plus'],
  'Geely': ['EX2', 'EX5', 'Geometry C', 'Geometry E'],
  'Volkswagen (VW)': ['ID3', 'ID4', 'ID6'],
  'Tesla': ['Model 3', 'Model Y', 'Model S', 'Model X'],
  'Nissan': ['Leaf', 'Ariya'],
  'Hyundai': ['Kona Electric', 'Ioniq 5', 'Ioniq 6'],
  'Kia': ['EV6', 'Niro EV', 'EV9'],
  'MG': ['MG4', 'MG ZS EV', 'MG5'],
  'NIO': ['ET5', 'ES6', 'ET7'],
  'XPeng': ['P7', 'G3', 'G6'],
  'Other': ['Other Model'],
};

// ---------------------------------------------------------------------
// LIVE data - starts out equal to the seed map above, and is replaced
// wholesale by CarModelsService.hydrate() once Firestore data loads (see
// services/car_models_service.dart). Every existing call site in the app
// (CarSetupScreen) keeps using the SAME name (`kCarBrandModels`) as
// before, so this is a drop-in change - no other file needs to import
// Firestore directly.
// ---------------------------------------------------------------------
Map<String, List<String>> _liveCarBrandModels = Map.of(kSeedCarBrandModels);

Map<String, List<String>> get kCarBrandModels => _liveCarBrandModels;

/// Called by CarModelsService once Firestore data has loaded (or been
/// seeded). Only overwrites the map if it's non-empty, so a transient
/// Firestore read failure never blanks out the Brand/Model dropdowns.
void applyLiveCarBrandModels(Map<String, List<String>> brandModels) {
  if (brandModels.isNotEmpty) _liveCarBrandModels = brandModels;
}
