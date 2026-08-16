import 'package:flutter/foundation.dart';
import '../models/car_profile.dart';
import '../models/charger_profile.dart';
import '../models/enums.dart';

enum AppRole { driver, host, admin }

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
  AppRole role = AppRole.driver;

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

  final List<ChargerProfile> chargers = [
    ChargerProfile(
      hostId: kCurrentUserId,
      chargerId: 'host_mohamed_villa',
      label: 'Villa Home Charger',
      powerKw: 22,
      ampere: 32,
      connector: ConnectorType.type2,
      city: 'Cairo',
      area: 'New Cairo',
      chargingStandard: ChargingStandard.europeanCcs2,
      pricingModel: PricingModel.perMinute,
      price: 2.5,
      latitude: kAreaCoordinates['New Cairo']!.lat + jitterOffsetFor('host_mohamed_villa').lat,
      longitude: kAreaCoordinates['New Cairo']!.lng + jitterOffsetFor('host_mohamed_villa').lng,
      mapLink: 'https://maps.google.com/?q=30.0131,31.4326',
    ),
    ChargerProfile(
      hostId: kCurrentUserId,
      chargerId: 'host_mohamed_garden',
      label: 'Garden Fast Charger',
      powerKw: 11,
      ampere: 16,
      connector: ConnectorType.type2,
      city: 'Cairo',
      area: 'New Cairo',
      chargingStandard: ChargingStandard.europeanCcs2,
      pricingModel: PricingModel.perKwh,
      price: 3.0,
      latitude: kAreaCoordinates['New Cairo']!.lat + jitterOffsetFor('host_mohamed_garden').lat,
      longitude: kAreaCoordinates['New Cairo']!.lng + jitterOffsetFor('host_mohamed_garden').lng,
    ),
    ChargerProfile(
      hostId: 'host_mona',
      chargerId: 'host_mona_garage',
      label: 'Garage Wallbox',
      powerKw: 11,
      ampere: 16,
      connector: ConnectorType.type2,
      city: 'Cairo',
      area: 'Maadi',
      chargingStandard: ChargingStandard.europeanCcs2,
      pricingModel: PricingModel.perMinute,
      price: 1.6,
      latitude: kAreaCoordinates['Maadi']!.lat + jitterOffsetFor('host_mona_garage').lat,
      longitude: kAreaCoordinates['Maadi']!.lng + jitterOffsetFor('host_mona_garage').lng,
    ),
    ChargerProfile(
      hostId: 'host_youssef',
      chargerId: 'host_youssef_compound',
      label: 'Compound Charger',
      powerKw: 7.4,
      ampere: 32,
      connector: ConnectorType.gbtDc,
      city: 'Cairo',
      area: 'Rehab City',
      chargingStandard: ChargingStandard.chineseGbT,
      pricingModel: PricingModel.perMinute,
      price: 1.2,
      latitude: kAreaCoordinates['Rehab City']!.lat + jitterOffsetFor('host_youssef_compound').lat,
      longitude: kAreaCoordinates['Rehab City']!.lng + jitterOffsetFor('host_youssef_compound').lng,
      residentsOnly: true,
      restrictedCommunity: 'Rehab City - Group 1',
    ),
  ];

  List<ChargerProfile> get myChargers => chargers.where((c) => c.hostId == kCurrentUserId).toList();

  void setRole(AppRole r) {
    role = r;
    notifyListeners();
  }

  void addCar(CarProfile c) {
    cars.add(c);
    activeCarId ??= c.carId;
    notifyListeners();
  }

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
