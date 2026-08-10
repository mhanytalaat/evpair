import 'dart:typed_data';
import 'enums.dart';
import 'availability_slot.dart';
import '../services/pricing_service.dart';

class ChargerProfile {
  final String hostId;
  final String chargerId;
  String label;
  double powerKw;
  double ampere;
  ConnectorType connector;
  String area;

  /// NEW: Chinese (GB/T) vs European (CCS2/Type 2) charging standard for
  /// this station. Hosts pick this explicitly on the Add/Edit Charger
  /// form since two chargers can look similar but be wired for
  /// completely different regional standards.
  ChargingStandard chargingStandard;

  PricingModel pricingModel;
  double price;

  /// Raw image bytes for the station photo, read via
  /// `XFile.readAsBytes()` and rendered with `Image.memory` - works
  /// identically on Web, Windows, Android, and iOS (unlike storing a file
  /// path and using `Image.file`).
  Uint8List? photoBytes;

  String? mapLink;

  double latitude;
  double longitude;

  bool residentsOnly;
  String? restrictedCommunity;

  final List<AvailabilitySlot> freeSlots;

  ChargerProfile({
    required this.hostId,
    required this.chargerId,
    required this.label,
    required this.powerKw,
    required this.ampere,
    required this.connector,
    required this.area,
    required this.chargingStandard,
    required this.pricingModel,
    required this.price,
    required this.latitude,
    required this.longitude,
    this.photoBytes,
    this.mapLink,
    this.residentsOnly = false,
    this.restrictedCommunity,
    List<AvailabilitySlot>? freeSlots,
  }) : freeSlots = freeSlots ?? [];

  bool get hasAnyFreeSlot => freeSlots.any((s) => !s.isBooked);

  bool isAccessibleToCommunity(String? driverCommunity) {
    if (!residentsOnly) return true;
    if (restrictedCommunity == null || driverCommunity == null) return false;
    return driverCommunity == restrictedCommunity;
  }

  AvailabilitySlot? findFittingSlot(DateTime reqStart, DateTime reqEnd) {
    final candidates = freeSlots.where((s) => s.canFit(reqStart, reqEnd)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return candidates.isEmpty ? null : candidates.first;
  }

  String get priceLabel => PricingService.priceLabel(pricingModel, price);
}
