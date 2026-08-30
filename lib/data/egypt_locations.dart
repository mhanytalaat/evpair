/// Curated list of Egyptian governorates/cities and their areas/
/// compounds, used everywhere a driver or host picks a location: the
/// Home screen station filter, the Home Installation & Equipment
/// service-request form, AND the host's Add/Edit Charger form. Keeping
/// this as a single shared data source means every part of the app uses
/// identical spelling, so filtering, search, and map placement all stay
/// consistent - a host picking "Cairo" / "New Cairo" for their charger
/// will always match a driver filtering by "Cairo" / "New Cairo".
///
/// NOTE ON FIRESTORE (item #2 of the 30/8 update): this file still ships
/// a bundled SEED list (`kSeedEgyptGovernorates` /
/// `kSeedGovernorateCoordinates`) so the app always has data even before
/// any network call completes. The values actually shown in the app are
/// the LIVE ones below (`kEgyptGovernorates` / `kGovernorateCoordinates`),
/// which start out equal to the seed list but get replaced with whatever
/// is in the Firestore `governorates` collection once
/// `LocationsService.hydrate()` runs (see services/locations_service.dart
/// and the call added in main.dart). On the very first run ever (empty
/// collection), LocationsService seeds Firestore FROM this file, so no
/// manual data entry is needed to get started - after that, editing a
/// governorate's `areas` array (or adding a new governorate document) in
/// the Firebase console updates every user's picker with no app release.
class EgyptGovernorate {
  final String name;
  final List<String> areas;
  final bool isPriority;
  const EgyptGovernorate({
    required this.name,
    required this.areas,
    this.isPriority = false,
  });
}

const List<EgyptGovernorate> kSeedEgyptGovernorates = [
  // ---------------------------------------------------------------
  // PRIORITY LOCATIONS
  // ---------------------------------------------------------------
  EgyptGovernorate(
    name: 'Cairo',
    isPriority: true,
    areas: [
      'Badr City',
      'Cairo Festival City',
      'Choueifat',
      'Downtown Cairo',
      'Fifth Settlement',
      'Garden City',
      'Heliopolis',
      'Hyde Park',
      'Katameya',
      'Katameya Heights',
      'Madinaty',
      'Maadi',
      'Mivida',
      'Mokattam',
      'Mountain View iCity',
      'Nasr City',
      'New Administrative Capital',
      'New Cairo',
      'Palm Hills New Cairo',
      'Rehab',
      'Sarai',
      'Sheraton',
      'Shorouk City',
      'Taj City',
      'Zamalek',
    ],
  ),
  EgyptGovernorate(
    name: 'Giza',
    isPriority: true,
    areas: [
      '6th October',
      'Agouza',
      'Allegria',
      'Beverly Hills',
      'Courtyards',
      'Dokki',
      'Faisal',
      'Haram',
      'Mohandessin',
      'Mountain View Chillout',
      'Mountain View October',
      'Palm Hills October',
      'Sheikh Zayed',
      'Smart Village',
      'Sodic West',
      'West Somid',
      'ZED West',
    ],
  ),
  EgyptGovernorate(
    name: 'North Coast (Matrouh)',
    isPriority: true,
    areas: [
      'Almaza Bay',
      'Amwaj',
      'Azha North Coast',
      'Bianchi',
      'Caesar Bay',
      'Direction White',
      'Fouka Bay',
      'Gaia',
      'Hacienda Bay',
      'Hacienda White',
      'Jefaira',
      'June Sodic',
      'Koun',
      'La Vista Bay',
      'La Vista Cascada',
      'LVLS',
      'Marina 1',
      'Marina 2',
      'Marina 3',
      'Marina 4',
      'Marina 5',
      'Marina 6',
      'Marina 7',
      'Marina 8',
      'Marassi',
      'Mountain View Ras El Hikma',
      'Porto Marina',
      'Ras El Hikma',
      'Salt',
      'Seashell',
      'Sidi Abdelrahman',
      'Silver Sands',
      'Stella Heights',
      'Swan Lake North Coast',
      'Telal',
      'Waterway North Coast',
      'New Alamein',
      'El Alamein',
    ],
  ),
  // ---------------------------------------------------------------
  // ALL OTHER GOVERNORATES (alphabetical)
  // ---------------------------------------------------------------
  EgyptGovernorate(name: 'Alexandria', areas: [
    'Agami', 'Borg El Arab', 'Gleem', 'Mandara', 'Miami', 'Montaza',
    'New Borg El Arab', 'Roushdy', 'San Stefano', 'Sidi Gaber', 'Smouha',
    'Sporting', 'Stanley',
  ]),
  EgyptGovernorate(name: 'Aswan', areas: ['Aswan', 'New Aswan']),
  EgyptGovernorate(name: 'Assiut', areas: ['Assiut City']),
  EgyptGovernorate(name: 'Beheira', areas: [
    'Damanhour', 'Edku', 'Kafr El Dawwar', 'Rashid',
  ]),
  EgyptGovernorate(name: 'Beni Suef', areas: ['Beni Suef', 'New Beni Suef']),
  EgyptGovernorate(name: 'Dakahlia', areas: [
    'Dekernes', 'Mansoura', 'Mit Ghamr', 'New Mansoura', 'Talkha',
  ]),
  EgyptGovernorate(name: 'Damietta', areas: [
    'Damietta', 'New Damietta', 'Ras El Bar',
  ]),
  EgyptGovernorate(name: 'Fayoum', areas: ['Fayoum City']),
  EgyptGovernorate(name: 'Gharbia', areas: [
    'El Mahalla El Kubra', 'Kafr El Zayat', 'Tanta',
  ]),
  EgyptGovernorate(name: 'Ismailia', areas: [
    'Abu Sultan', 'El Qantara East', 'El Qantara West', 'Fayed', 'Ismailia',
  ]),
  EgyptGovernorate(name: 'Kafr El Sheikh', areas: [
    'Baltim', 'Desouk', 'Kafr El Sheikh',
  ]),
  EgyptGovernorate(name: 'Luxor', areas: ['Luxor East Bank', 'Luxor West Bank']),
  EgyptGovernorate(
    name: 'Matrouh (excluding North Coast resorts already listed)',
    areas: ['Marsa Matrouh', 'Siwa'],
  ),
  EgyptGovernorate(name: 'Menoufia', areas: [
    'Menouf', 'Sadat City', 'Shebin El Kom',
  ]),
  EgyptGovernorate(name: 'Minya', areas: ['Minya', 'New Minya']),
  EgyptGovernorate(name: 'New Valley', areas: ['Dakhla', 'Farafra', 'Kharga']),
  EgyptGovernorate(name: 'North Sinai', areas: [
    'Arish', 'Rafah', 'Sheikh Zuweid',
  ]),
  EgyptGovernorate(name: 'Port Said', areas: ['Port Fouad', 'Port Said']),
  EgyptGovernorate(name: 'Qalyubia', areas: [
    'Banha', 'Obour City', 'Qalyub', 'Shubra El Kheima',
  ]),
  EgyptGovernorate(name: 'Qena', areas: ['Nag Hammadi', 'Qena']),
  EgyptGovernorate(name: 'Red Sea', areas: [
    'El Gouna', 'El Quseir', 'Hurghada', 'Makadi Bay', 'Marsa Alam',
    'Port Ghalib', 'Safaga', 'Sahl Hasheesh', 'Soma Bay',
  ]),
  EgyptGovernorate(name: 'Sharqia', areas: [
    '10th of Ramadan', 'Abu Hammad', 'Belbeis', 'Minya El Qamh', 'Zagazig',
  ]),
  EgyptGovernorate(name: 'Sohag', areas: ['Akhmim', 'Sohag']),
  EgyptGovernorate(name: 'South Sinai', areas: [
    'Dahab', 'El Tor', 'Hadaba', 'Naama Bay', 'Nabq', 'Nuweiba',
    'Ras Sedr', 'Sharm El Sheikh', 'Sharks Bay', 'Soho Square', 'Taba',
  ]),
  EgyptGovernorate(name: 'Suez', areas: [
    'Ain Sokhna', 'Azha Sokhna', 'Galala', 'IL Monte Galala',
    'La Vista Sokhna', 'Porto Sokhna', 'Suez', 'Telal Ain Sokhna',
  ]),
];

/// Approximate center point for each governorate/region, used to place a
/// new charger's map pin when the host hasn't picked an exact pin (see
/// ChargerFormScreen._resolveCoordinates). A small random jitter
/// (jitterOffsetFor in state/app_state.dart) is applied on top so
/// multiple chargers in the same governorate don't all stack on the
/// exact same point.
const Map<String, ({double lat, double lng})> kSeedGovernorateCoordinates = {
  'Cairo': (lat: 30.0444, lng: 31.2357),
  'Giza': (lat: 30.0131, lng: 31.2089),
  'North Coast (Matrouh)': (lat: 30.8481, lng: 28.9540),
  'Alexandria': (lat: 31.2001, lng: 29.9187),
  'Aswan': (lat: 24.0889, lng: 32.8998),
  'Assiut': (lat: 27.1809, lng: 31.1837),
  'Beheira': (lat: 30.8481, lng: 30.3436),
  'Beni Suef': (lat: 29.0661, lng: 31.0994),
  'Dakahlia': (lat: 31.0409, lng: 31.3785),
  'Damietta': (lat: 31.4165, lng: 31.8133),
  'Fayoum': (lat: 29.3084, lng: 30.8441),
  'Gharbia': (lat: 30.7865, lng: 31.0004),
  'Ismailia': (lat: 30.5965, lng: 32.2715),
  'Kafr El Sheikh': (lat: 31.1107, lng: 30.9388),
  'Luxor': (lat: 25.6872, lng: 32.6396),
  'Matrouh (excluding North Coast resorts already listed)': (lat: 31.3543, lng: 27.2373),
  'Menoufia': (lat: 30.5972, lng: 30.9876),
  'Minya': (lat: 28.0871, lng: 30.7618),
  'New Valley': (lat: 25.4515, lng: 30.5467),
  'North Sinai': (lat: 31.1316, lng: 33.7984),
  'Port Said': (lat: 31.2653, lng: 32.3019),
  'Qalyubia': (lat: 30.1792, lng: 31.2044),
  'Qena': (lat: 26.1551, lng: 32.7160),
  'Red Sea': (lat: 27.2579, lng: 33.8116),
  'Sharqia': (lat: 30.7327, lng: 31.3357),
  'Sohag': (lat: 26.5569, lng: 31.6948),
  'South Sinai': (lat: 28.3428, lng: 33.9330),
  'Suez': (lat: 29.9668, lng: 32.5498),
};

// ---------------------------------------------------------------------
// LIVE data - starts out equal to the seed lists above, and is replaced
// wholesale by LocationsService.hydrate() once Firestore data loads (see
// services/locations_service.dart). Every existing call site in the app
// (LocationPickerField, ChargerFormScreen, etc.) keeps using the SAME
// names (`kEgyptGovernorates`, `kGovernorateCoordinates`) as before, so
// this is a drop-in change - no other file needs to import Firestore
// directly.
// ---------------------------------------------------------------------
List<EgyptGovernorate> _liveGovernorates = List.of(kSeedEgyptGovernorates);
Map<String, ({double lat, double lng})> _liveGovernorateCoordinates = Map.of(kSeedGovernorateCoordinates);

List<EgyptGovernorate> get kEgyptGovernorates => _liveGovernorates;
Map<String, ({double lat, double lng})> get kGovernorateCoordinates => _liveGovernorateCoordinates;

/// Called by LocationsService once Firestore data has loaded (or been
/// seeded). Only overwrites a list if it's non-empty, so a transient
/// Firestore read failure never blanks out the picker.
void applyLiveGovernorates(
  List<EgyptGovernorate> governorates,
  Map<String, ({double lat, double lng})> coordinates,
) {
  if (governorates.isNotEmpty) _liveGovernorates = governorates;
  if (coordinates.isNotEmpty) _liveGovernorateCoordinates = coordinates;
}

List<String> get kAllGovernorateNames => kEgyptGovernorates.map((g) => g.name).toList();

List<String> areasFor(String? governorate) {
  if (governorate == null) return const [];
  for (final g in kEgyptGovernorates) {
    if (g.name == governorate) return g.areas;
  }
  return const [];
}

bool isKnownGovernorate(String? name) => name != null && kAllGovernorateNames.contains(name);

bool isKnownArea(String? governorate, String? area) =>
    area != null && areasFor(governorate).contains(area);
