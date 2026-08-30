/// Charger power (kW) options offered in the "Power (kW)" dropdown on
/// Add/Edit Charger (see screens/host/charger_form_screen.dart).
///
/// Same live-data pattern as data/egypt_locations.dart: this file still
/// ships a bundled SEED list (`kSeedPowerOptions`) so the app always has
/// values even before any network call completes. The value actually
/// shown in the app is the LIVE list (`kPowerOptions`), which starts out
/// equal to the seed list but gets replaced with whatever is in the
/// Firestore `appSettings/chargerPowerOptions` document once
/// PowerOptionsService.hydrate() runs (see
/// services/power_options_service.dart and the call added in main.dart).
///
/// On the very first run ever (document doesn't exist), PowerOptionsService
/// seeds Firestore FROM this file, so no manual data entry is needed to
/// get started - after that, editing the `values` array in the Firebase
/// console (e.g. adding 150 for a new DC fast-charger) updates every
/// host's "Power (kW)" dropdown with no app release.
const List<double> kSeedPowerOptions = [3.3, 7.4, 11, 22, 50, 100];

List<double> _livePowerOptions = List.of(kSeedPowerOptions);

/// This is what every screen actually reads (ChargerFormScreen's "Power
/// (kW)" dropdown, via the `export` in state/app_state.dart - no other
/// file needs to change its imports).
List<double> get kPowerOptions => _livePowerOptions;

/// Called by PowerOptionsService once Firestore data has loaded (or been
/// seeded). Only overwrites the list if it's non-empty, so a transient
/// Firestore read failure never blanks out the dropdown.
void applyLivePowerOptions(List<double> values) {
  if (values.isNotEmpty) {
    final sorted = List.of(values)..sort();
    _livePowerOptions = sorted;
  }
}
