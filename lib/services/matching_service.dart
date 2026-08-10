import 'package:geolocator/geolocator.dart';
import '../models/car_profile.dart';
import '../models/charger_profile.dart';
import '../models/availability_slot.dart';

class ChargerMatch {
  final ChargerProfile charger;
  final double distanceKm;
  final AvailabilitySlot fittingSlot;

  ChargerMatch({required this.charger, required this.distanceKm, required this.fittingSlot});
}

class MatchingService {
  List<ChargerMatch> findMatches({
    required CarProfile car,
    required List<ChargerProfile> allChargers,
    required double driverLat,
    required double driverLng,
    required DateTime requestedStart,
    required DateTime requestedEnd,
  }) {
    final matches = <ChargerMatch>[];
    for (final charger in allChargers) {
      if (!car.isCompatibleWithAmpere(charger.ampere, charger.connector)) continue;
      // NEW: also require the charging STANDARD (Chinese GB/T vs European
      // CCS2/Type 2) to match - a car and charger can otherwise "look"
      // compatible on ampere/connector but be physically unusable
      // together (e.g. an Arcfox T1 on GB/T vs a European CCS2 station).
      if (!car.isCompatibleStandard(charger.chargingStandard)) continue;
      if (!charger.isAccessibleToCommunity(car.community)) continue;
      final slot = charger.findFittingSlot(requestedStart, requestedEnd);
      if (slot == null) continue;
      final distanceMeters = Geolocator.distanceBetween(driverLat, driverLng, charger.latitude, charger.longitude);
      matches.add(ChargerMatch(charger: charger, distanceKm: distanceMeters / 1000, fittingSlot: slot));
    }
    matches.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return matches;
  }

  List<ChargerProfile> compatibleChargersForMap({
    required CarProfile car,
    required List<ChargerProfile> allChargers,
  }) {
    return allChargers
        .where((c) => car.connector == c.connector && c.ampere <= car.maxAmpere + 0.01 && car.isCompatibleStandard(c.chargingStandard))
        .toList();
  }
}
