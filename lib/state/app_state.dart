import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/car_profile.dart';
import '../models/charger_profile.dart';
export '../data/charger_power_options.dart' show kPowerOptions;
export '../data/car_brand_models.dart' show kCarBrandModels;

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

({double lat, double lng}) jitterOffsetFor(String seed) {
  final hash = seed.hashCode;
  final dx = ((hash % 2000) / 1000.0 - 1.0) * 0.012;
  final dy = (((hash ~/ 2000) % 2000) / 1000.0 - 1.0) * 0.012;
  return (lat: dy, lng: dx);
}

const List<double> kAmpereOptions = [16, 32, 63];

class AppState extends ChangeNotifier {
  AppState({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  bool isHydrating = true;
  AppRole role = AppRole.driver;
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

  final List<ChargerProfile> chargers = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chargersSubscription;

  List<ChargerProfile> get myChargers =>
      currentUserId == null ? const [] : chargers.where((c) => c.hostId == currentUserId).toList();

  void setRole(AppRole r) {
    role = r;
    notifyListeners();
  }

  Future<void> hydrateFromFirestore() async {
    isHydrating = true;
    notifyListeners();
    try {
      await _listenToChargers();
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

  Future<void> _listenToChargers() {
    final completer = Completer<void>();
    _chargersSubscription?.cancel();
    _chargersSubscription = _db.collection('chargers').snapshots().listen(
      (snapshot) {
        chargers
          ..clear()
          ..addAll(snapshot.docs.map((d) => ChargerProfile.fromFirestore(d.data())));
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
      },
      onError: (e) {
        debugPrint('AppState: chargers listener error: $e');
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  @override
  void dispose() {
    _chargersSubscription?.cancel();
    super.dispose();
  }

  Future<void> setCurrentUserAndHydrate(String userId) async {
    currentUserId = userId;
    await hydrateFromFirestore();
  }

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

  /// Awaits the Firestore write and REthrows on failure (instead of the
  /// previous fire-and-forget version, which could never report a
  /// rejected write - the charger just silently vanished later when the
  /// real-time listener resynced from the server). On failure, the
  /// optimistic local add is rolled back so the list never shows a
  /// charger that isn't actually saved.
  Future<void> addCharger(ChargerProfile c) async {
    chargers.add(c);
    notifyListeners();
    try {
      await _db.collection('chargers').doc(c.chargerId).set(c.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      chargers.removeWhere((existing) => existing.chargerId == c.chargerId);
      notifyListeners();
      rethrow;
    }
  }

  /// Same fix as addCharger: awaited and rethrown.
  Future<void> updateCharger(ChargerProfile updated) async {
    notifyListeners();
    await _db.collection('chargers').doc(updated.chargerId).set(updated.toFirestore(), SetOptions(merge: true));
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
