import 'package:cloud_firestore/cloud_firestore.dart';
import 'enums.dart';

class CarProfile {
  final String carId;
  final String driverId;
  final String brand;
  final String model;
  final String plateNumber;
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
    required this.plateNumber,
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

  /// Firestore document shape for the `cars` collection. Field names match
  /// what is actually used in the UI (see CarSetupScreen/MyCarsScreen)
  /// rather than a generic placeholder schema.
  Map<String, dynamic> toFirestore() {
    return {
      'carId': carId,
      'driverId': driverId,
      'brand': brand,
      'model': model,
      'plateNumber': plateNumber,
      'maxAmpere': maxAmpere,
      'rangeKm': rangeKm,
      'connector': connector.name,
      'chargingStandard': chargingStandard.name,
      'community': community,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory CarProfile.fromFirestore(Map<String, dynamic> data) {
    return CarProfile(
      carId: data['carId'] as String,
      driverId: data['driverId'] as String,
      brand: data['brand'] as String,
      model: data['model'] as String,
      plateNumber: data['plateNumber'] as String? ?? '',
      maxAmpere: (data['maxAmpere'] as num).toDouble(),
      rangeKm: (data['rangeKm'] as num).toDouble(),
      connector: ConnectorType.values.byName(data['connector'] as String),
      chargingStandard: ChargingStandard.values.byName(data['chargingStandard'] as String),
      community: data['community'] as String?,
    );
  }
}
