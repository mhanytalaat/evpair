import 'package:flutter/foundation.dart';
import '../models/car_profile.dart';
import '../models/charger_profile.dart';
import '../models/enums.dart';

/// The 3 top-level tabs, mirroring the HTML demo's bottom nav (Driver /
/// Host / Admin). NOTE: in a real production consumer app, Admin would
/// NOT be a selectable tab here at all. See screens/admin/ notes.
enum AppRole { driver, host, admin }

/// Single account id used for BOTH the driver profile and the host's
/// charger(s), confirming a user can be a driver (owns car(s)) AND a host
/// (rents out a charger) at the same time.
const String kCurrentUserId = 'mohamed_hany';

const List<String> kCommunityOptions = [
  'Rehab City - Group 1',
  'Rehab City - Group 5',
  'Katameya Heights',
  'Marassi Compound',
  'Palm Hills October',
  'Mivida',
  'Other Compound',
];

const List<String> kAreaOptions = [
  'New Cairo', 'Maadi', 'Sheikh Zayed', 'Rehab City', 'New Capital',
  'Zamalek', '6th of October', 'Katameya', 'Other',
];

/// Approximate real-world coordinates for the CENTER of each area option.
/// Used as a fallback when a host does not paste a Google Maps link with
/// precise coordinates. See `jitterOffsetFor()` below - individual
/// chargers within the same area are nudged a small, deterministic amount
/// away from this exact center point so they appear SPREAD OUT within the
/// district on the map (rather than all stacking on the exact same pixel),
/// which is what a driver would realistically expect to see.
const Map<String, ({double lat, double lng})> kAreaCoordinates = {
  'New Cairo': (lat: 30.0131, lng: 31.4326),
  'Maadi': (lat: 29.9602, lng: 31.2569),
  'Sheikh Zayed': (lat: 30.0778, lng: 30.9757),
  'Rehab City': (lat: 30.0566, lng: 31.4913),
  'New Capital': (lat: 30.0131, lng: 31.7051),
  'Zamalek': (lat: 30.0626, lng: 31.2197),
  '6th of October': (lat: 29.9660, lng: 30.9232),
  'Katameya': (lat: 29.9700, lng: 31.3400),
  'Other': (lat: 30.0444, lng: 31.2357), // Cairo center fallback
};

/// Deterministic small offset (roughly +/- 0.5-1.5 km) derived from a
/// seed string (typically a charger's id), so that multiple chargers
/// falling back to the SAME area-center coordinate are nudged to visually
/// distinct positions "within the district" instead of stacking exactly
/// on top of one another. Deterministic (not random) so a given charger's
/// pin position doesn't jump around every time the app rebuilds. Callers
/// add the returned lat/lng deltas to a base coordinate themselves, e.g.
/// `kAreaCoordinates['New Cairo']!.lat + jitterOffsetFor(id).lat`.
({double lat, double lng}) jitterOffsetFor(String seed) {
  final hash = seed.hashCode;
  // Two independent-ish pseudo-random values in [-1, 1] derived from the
  // hash, scaled to roughly +/-0.012 degrees (~1.2 km) - enough to visibly
  // separate pins within a district without leaving the district itself.
  final dx = ((hash % 2000) / 1000.0 - 1.0) * 0.012;
  final dy = (((hash ~/ 2000) % 2000) / 1000.0 - 1.0) * 0.012;
  return (lat: dy, lng: dx);
}

/// Power (kW) options for the charger form.
const List<double> kPowerOptions = [3.3, 7.4, 11, 22, 50, 100];
const List<double> kAmpereOptions = [16, 32, 63];

/// Car Brand -> Model options, driving the cascading dropdown on the Car
/// Profile screen.
const Map<String, List<String>> kCarBrandModels = {
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

/// Holds ONLY navigation-tab state (which of the 3 bottom-nav tabs is
/// active) and shared domain data - the driver's car(s), the list of
/// chargers, which booking the driver last made. Screen-to-screen
/// navigation WITHIN a tab is handled by Flutter's normal
/// Navigator.push()/pop().
class AppState extends ChangeNotifier {
  AppRole role = AppRole.driver;

  /// NEW: a driver can now own MULTIPLE cars (previously a single
  /// nullable `CarProfile? car` field). `activeCarId` tracks which one is
  /// currently used for map compatibility checks and new bookings; it
  /// defaults to the first car added and can be changed via
  /// `setActiveCar()` on the new MyCarsScreen.
  final List<CarProfile> cars = [];
  String? activeCarId;

  String? lastDriverBookingId;

  /// Backward-compatible getter: every existing screen that reads
  /// `app.car` (map compatibility checks, booking creation, etc.)
  /// continues to work unmodified - it now resolves to whichever car is
  /// "active", or null if the driver hasn't added any car yet.
  CarProfile? get car {
    if (cars.isEmpty) return null;
    if (activeCarId == null) return cars.first;
    try {
      return cars.firstWhere((c) => c.carId == activeCarId);
    } catch (_) {
      return cars.first;
    }
  }

  final List<ChargerProfile> chargers = [
    ChargerProfile(
      hostId: kCurrentUserId,
      chargerId: 'host_mohamed_villa',
      label: 'Villa Home Charger',
      powerKw: 22,
      ampere: 32,
      connector: ConnectorType.type2,
      chargingStandard: ChargingStandard.europeanCcs2,
      area: 'New Cairo',
      pricingModel: PricingModel.perMinute,
      price: 2.5,
      latitude: kAreaCoordinates['New Cairo']!.lat +
          jitterOffsetFor('host_mohamed_villa').lat,
      longitude: kAreaCoordinates['New Cairo']!.lng +
          jitterOffsetFor('host_mohamed_villa').lng,
    ),
    ChargerProfile(
      hostId: kCurrentUserId,
      chargerId: 'host_mohamed_garden',
      label: 'Garden Fast Charger',
      powerKw: 11,
      ampere: 16,
      connector: ConnectorType.type2,
      chargingStandard: ChargingStandard.europeanCcs2,
      area: 'New Cairo',
      pricingModel: PricingModel.perKwh,
      price: 3.0,
      latitude: kAreaCoordinates['New Cairo']!.lat +
          jitterOffsetFor('host_mohamed_garden').lat,
      longitude: kAreaCoordinates['New Cairo']!.lng +
          jitterOffsetFor('host_mohamed_garden').lng,
    ),
    ChargerProfile(
      hostId: 'host_mona',
      chargerId: 'host_mona_garage',
      label: 'Garage Wallbox',
      powerKw: 11,
      ampere: 16,
      connector: ConnectorType.type2,
      chargingStandard: ChargingStandard.europeanCcs2,
      area: 'Maadi',
      pricingModel: PricingModel.perMinute,
      price: 1.6,
      latitude: kAreaCoordinates['Maadi']!.lat +
          jitterOffsetFor('host_mona_garage').lat,
      longitude: kAreaCoordinates['Maadi']!.lng +
          jitterOffsetFor('host_mona_garage').lng,
    ),
    ChargerProfile(
      hostId: 'host_youssef',
      chargerId: 'host_youssef_compound',
      label: 'Compound Charger',
      powerKw: 7.4,
      ampere: 32,
      connector: ConnectorType.gbtDc,
      chargingStandard: ChargingStandard.chineseGbT,
      area: 'Rehab City',
      pricingModel: PricingModel.perMinute,
      price: 1.2,
      latitude: kAreaCoordinates['Rehab City']!.lat +
          jitterOffsetFor('host_youssef_compound').lat,
      longitude: kAreaCoordinates['Rehab City']!.lng +
          jitterOffsetFor('host_youssef_compound').lng,
      residentsOnly: true,
      restrictedCommunity: 'Rehab City - Group 1',
    ),
  ];

  List<ChargerProfile> get myChargers => chargers.where((c) => c.hostId == kCurrentUserId).toList();

  void setRole(AppRole r) {
    role = r;
    notifyListeners();
  }

  // ---- Multi-car management ----

  void addCar(CarProfile c) {
    cars.add(c);
    activeCarId ??= c.carId;
    notifyListeners();
  }

  /// Replaces an existing car (matched by carId) with an updated copy -
  /// used when editing a car from MyCarsScreen.
  void updateCar(CarProfile updated) {
    final idx = cars.indexWhere((c) => c.carId == updated.carId);
    if (idx != -1) cars[idx] = updated;
    notifyListeners();
  }

  void removeCar(String carId) {
    cars.removeWhere((c) => c.carId == carId);
    if (activeCarId == carId) {
      activeCarId = cars.isEmpty ? null : cars.first.carId;
    }
    notifyListeners();
  }

  void setActiveCar(String carId) {
    activeCarId = carId;
    notifyListeners();
  }

  void addCharger(ChargerProfile c) {
    chargers.add(c);
    notifyListeners();
  }

  void setLastDriverBooking(String bookingId) {
    lastDriverBookingId = bookingId;
    notifyListeners();
  }
}
