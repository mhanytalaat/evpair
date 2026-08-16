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

  String city;
  String area;

  ChargingStandard chargingStandard;

  PricingModel pricingModel;
  double price;

  Uint8List? photoBytes;

  /// Host-provided Google Maps link. When present, this is the source of
  /// TRUTH for map placement (parsed for exact coordinates) - it takes
  /// priority over the City/Area-based fallback.
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
    required this.city,
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

  bool get hasAnyFreeSlot => freeSlots.isNotEmpty;

  bool isAccessibleToCommunity(String? driverCommunity) {
    if (!residentsOnly) return true;
    if (restrictedCommunity == null || driverCommunity == null) return false;
    return driverCommunity == restrictedCommunity;
  }

  /// Finds a host-defined window that fully contains [reqStart]-[reqEnd].
  /// Does NOT check for overlaps with other bookings within that window -
  /// see BookingService.isRangeAvailable() for the full check.
  AvailabilitySlot? findFittingSlot(DateTime reqStart, DateTime reqEnd) {
    final candidates = freeSlots.where((s) => s.canFit(reqStart, reqEnd)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return candidates.isEmpty ? null : candidates.first;
  }

  String get priceLabel => PricingService.priceLabel(pricingModel, price);
}
