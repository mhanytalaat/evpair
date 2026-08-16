import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/car_profile.dart';
import '../models/charger_profile.dart';

enum AppRole { driver, host, admin }

const List<String> kCommunityOptions = [
  'Rehab City - Group 1',
  'Rehab City - Group 5',
  'Katameya Heights',
  'Marassi Compound',
  'Palm Hills October',
  'Mivida',
  'Other Compound',
];

const Map<String, List<String>> kCityAreaOptions = {
  'Cairo': ['New Cairo', 'Maadi', 'Zamalek', 'Nasr City', 'Heliopolis', 'Rehab City', 'Katameya', 'Other Cairo'],
  'Giza': ['Sheikh Zayed', '6th of October', 'Mohandessin', 'Dokki', 'Haram', 'Other Giza'],
  'Alexandria': ['Smouha', 'Stanley', 'Gleem', 'Miami', 'Sidi Gaber', 'Other Alexandria'],
  'New Capital': ['Downtown', 'R7', 'R8', 'Diplomatic District', 'Other New Capital'],
  'Red Sea': ['Hurghada', 'El Gouna', 'Sahl Hasheesh', 'Makadi Bay', 'Other Red Sea'],
  'North Coast': ['Marassi', 'Hacienda', 'New Alamein', 'Sidi Abdelrahman', 'Other North Coast'],
  'Other': ['Other'],
};

const List<String> kCityOptions = ['Cairo', 'Giza', 'Alexandria', 'New Capital', 'Red Sea', 'North Coast', 'Other'];

const Map<String, ({double lat, double lng})> kAreaCoordinates = {
  'New Cairo': (lat: 30.0131, lng: 31.4326),
  'Maadi': (lat: 29.9602, lng: 31.2569),
  'Zamalek': (lat: 30.0626, lng: 31.2197),
  'Nasr City': (lat: 30.0561, lng: 31.3300),
  'Heliopolis': (lat: 30.0910, lng: 31.3225),
  'Rehab City': (lat: 30.0566, lng: 31.4913),
  'Katameya': (lat: 29.9700, lng: 31.3400),
  'Other Cairo': (lat: 30.0444, lng: 31.2357),
  'Sheikh Zayed': (lat: 30.0778, lng: 30.9757),
  '6th of October': (lat: 29.9660, lng: 30.9232),
  'Mohandessin': (lat: 30.0551, lng: 31.2000),
  'Dokki': (lat: 30.0384, lng: 31.2115),
  'Haram': (lat: 29.9950, lng: 31.1510),
  'Other Giza': (lat: 30.0131, lng: 31.2089),
  'Smouha': (lat: 31.2070, lng: 29.9450),
  'Stanley': (lat: 31.2240, lng: 29.9600),
  'Gleem': (lat: 31.2340, lng: 29.9560),
  'Miami': (lat: 31.2600, lng: 29.9900),
  'Sidi Gaber': (lat: 31.2182, lng: 29.9420),
  'Other Alexandria': (lat: 31.2001, lng: 29.9187),
  'Downtown': (lat: 30.0131, lng: 31.7051),
  'R7': (lat: 30.0080, lng: 31.6900),
  'R8': (lat: 29.9950, lng: 31.7100),
  'Diplomatic District': (lat: 30.0200, lng: 31.7300),
  'Other New Capital': (lat: 30.0131, lng: 31.7051),
  'Hurghada': (lat: 27.2579, lng: 33.8116),
  'El Gouna': (lat: 27.3942, lng: 33.6782),
  'Sahl Hasheesh': (lat: 27.0450, lng: 33.8900),
  'Makadi Bay': (lat: 26.9910, lng: 33.8990),
  'Other Red Sea': (lat: 27.2579, lng: 33.8116),
  'Marassi': (lat: 30.9740, lng: 28.7480),
  'Hacienda': (lat: 30.9350, lng: 28.7700),
  'New Alamein': (lat: 30.8300, lng: 28.9550),
  'Sidi Abdelrahman': (lat: 30.9300, lng: 28.8300),
  'Other North Coast': (lat: 30.8500, lng: 29.0000),
  'Other': (lat: 30.0444, lng: 31.2357),
};

({double lat, double lng}) jitterOffsetFor(String seed) {
  final hash = seed.hashCode;
  final dx = ((hash % 2000) / 1000.0 - 1.0) * 0.012;
  final dy = (((hash ~/ 2000) % 2000) / 1000.0 - 1.0) * 0.012;
  return (lat: dy, lng: dx);
}

const List<double> kPowerOptions = [3.3, 7.4, 11, 22, 50, 100];
const List<double> kAmpereOptions = [16, 32, 63];

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

class AppState extends ChangeNotifier {
  AppState({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// True while cars/chargers are being loaded from Firestore.
  bool isHydrating = true;

  AppRole role = AppRole.driver;

  /// The Firebase Auth uid of the currently signed-in user, or null for a
  /// guest. Car ownership (`cars.driverId`) and charger ownership
  /// (`chargers.hostId`) are both keyed to this id - see
  /// setCurrentUserAndHydrate/clearCurrentUserAndData, called from the
  /// Register/Sign In/Sign Out flows in AuthService's callers.
  String? currentUserId;

  final List<CarProfile> cars = [];
  String? activeCarId;

  String? lastDriverBookingId;

  CarProfile? get car {
    if (cars.isEmpty) return null;
    if (activeCarId == null) return cars.first;
    try {
      return cars.firstWhere((c) => c.carId == activeCarId);
    } catch (_) {
      return cars.first;
    }
  }

  /// ALL chargers in the marketplace (every host), loaded from Firestore.
  /// There is no bundled demo/seed data - this starts empty and only ever
  /// contains chargers that hosts have actually added via
  /// ChargerFormScreen.
  final List<ChargerProfile> chargers = [];

  List<ChargerProfile> get myChargers =>
      currentUserId == null ? const [] : chargers.where((c) => c.hostId == currentUserId).toList();

  void setRole(AppRole r) {
    role = r;
    notifyListeners();
  }

  /// Loads marketplace chargers (every host - drivers need to see all of
  /// them to browse/book) and, if signed in, this user's own cars from
  /// Firestore. Called on app start and again whenever the signed-in user
  /// changes (see setCurrentUserAndHydrate/clearCurrentUserAndData).
  Future<void> hydrateFromFirestore() async {
    isHydrating = true;
    notifyListeners();

    try {
      final chargersSnapshot = await _db.collection('chargers').get();
      chargers
        ..clear()
        ..addAll(chargersSnapshot.docs.map((d) => ChargerProfile.fromFirestore(d.data())));

      if (currentUserId != null) {
        final carsSnapshot = await _db.collection('cars').where('driverId', isEqualTo: currentUserId).get();
        cars
          ..clear()
          ..addAll(carsSnapshot.docs.map((d) => CarProfile.fromFirestore(d.data())));
        activeCarId = cars.isEmpty ? null : cars.first.carId;
      } else {
        cars.clear();
        activeCarId = null;
      }
    } catch (e) {
      debugPrint('AppState.hydrateFromFirestore failed: $e');
    }

    isHydrating = false;
    notifyListeners();
  }

  /// Call right after a successful register()/signIn() so this user's own
  /// cars (and their view of the marketplace) load correctly.
  Future<void> setCurrentUserAndHydrate(String userId) async {
    currentUserId = userId;
    await hydrateFromFirestore();
  }

  /// Call right after signOut(). Clears private data (cars) and resets out
  /// of the Host/Admin tabs; the charger marketplace list is left as-is
  /// since browsing chargers doesn't require an account.
  Future<void> clearCurrentUserAndData() async {
    currentUserId = null;
    cars.clear();
    activeCarId = null;
    role = AppRole.driver;
    notifyListeners();
  }

  void addCar(CarProfile c) {
    cars.add(c);
    activeCarId ??= c.carId;
    notifyListeners();
    _db.collection('cars').doc(c.carId).set(c.toFirestore(), SetOptions(merge: true));
  }

  void updateCar(CarProfile updated) {
    final idx = cars.indexWhere((c) => c.carId == updated.carId);
    if (idx != -1) cars[idx] = updated;
    notifyListeners();
    _db.collection('cars').doc(updated.carId).set(updated.toFirestore(), SetOptions(merge: true));
  }

  void removeCar(String carId) {
    cars.removeWhere((c) => c.carId == carId);
    if (activeCarId == carId) {
      activeCarId = cars.isEmpty ? null : cars.first.carId;
    }
    notifyListeners();
    _db.collection('cars').doc(carId).delete();
  }

  void setActiveCar(String carId) {
    activeCarId = carId;
    notifyListeners();
  }

  void addCharger(ChargerProfile c) {
    chargers.add(c);
    notifyListeners();
    _db.collection('chargers').doc(c.chargerId).set(c.toFirestore(), SetOptions(merge: true));
  }

  /// Persists in-place edits made to an existing ChargerProfile (see
  /// ChargerFormScreen, which mutates the object's fields directly rather
  /// than constructing a new instance).
  void updateCharger(ChargerProfile updated) {
    notifyListeners();
    _db.collection('chargers').doc(updated.chargerId).set(updated.toFirestore(), SetOptions(merge: true));
  }

  void removeCharger(String chargerId) {
    chargers.removeWhere((c) => c.chargerId == chargerId);
    notifyListeners();
    _db.collection('chargers').doc(chargerId).delete();
  }

  void setLastDriverBooking(String bookingId) {
    lastDriverBookingId = bookingId;
    notifyListeners();
  }
}
