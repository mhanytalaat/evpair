import 'enums.dart';

class CarProfile {
  final String carId;
  final String driverId;
  final String brand;
  final String model;
  final double maxAmpere;
  final double rangeKm;
  final ConnectorType connector;
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

  String get carModel => '$brand $model';

  bool isCompatibleWithAmpere(double chargerAmpere, ConnectorType chargerConnector) {
    return connector == chargerConnector && chargerAmpere <= maxAmpere + 0.01;
  }

  bool isCompatibleStandard(ChargingStandard chargerStandard) => chargingStandard == chargerStandard;
}
