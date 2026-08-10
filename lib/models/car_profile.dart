import 'enums.dart';

class CarProfile {
  /// NEW: unique identity for this specific car, so a driver can own
  /// MULTIPLE cars (see AppState.cars / MyCarsScreen). Required so we can
  /// tell cars apart for editing/selecting an "active" car, since brand +
  /// model alone isn't unique (a driver could own two of the same model).
  final String carId;

  final String driverId;

  /// Brand and model are separate fields, driving the cascading Brand ->
  /// Model dropdown on the Car Profile screen (e.g. "Volkswagen (VW)" ->
  /// "ID4", "Geely" -> "EX5", "Arcfox" -> "T1").
  final String brand;
  final String model;

  final double maxAmpere;
  final double rangeKm;
  final ConnectorType connector;

  /// Chinese (GB/T) vs European (CCS2/Type 2) charging standard. This is a
  /// DIFFERENT axis of compatibility from `connector` - a car and a
  /// charger must match on BOTH to actually work together.
  final ChargingStandard chargingStandard;

  final String? community;

  CarProfile({
    required this.carId,
    required this.driverId,
    required this.brand,
    required this.model,
    required this.maxAmpere,
    required this.rangeKm,
    required this.connector,
    required this.chargingStandard,
    this.community,
  });

  /// Backward-compatible display string (e.g. "Volkswagen (VW) ID4").
  String get carModel => '$brand $model';

  bool isCompatibleWithAmpere(double chargerAmpere, ConnectorType chargerConnector) {
    return connector == chargerConnector && chargerAmpere <= maxAmpere + 0.01;
  }

  /// Whether this car's charging STANDARD (Chinese GB/T vs European
  /// CCS2/Type 2) matches a given charger's standard.
  bool isCompatibleStandard(ChargingStandard chargerStandard) => chargingStandard == chargerStandard;
}
