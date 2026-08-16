import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// Firestore document shape for the `chargers` collection. Field names
  /// match what is actually used in the UI (ChargerFormScreen /
  /// ManageChargerScreen / DriverHomeScreen map+list) rather than a
  /// generic placeholder schema.
  ///
  /// Note: `photoBytes` is stored inline as base64 for now (no
  /// firebase_storage dependency yet). This is fine for typical
  /// compressed station photos but will hit Firestore's ~1MB document
  /// limit for very large images - migrating to Firebase Storage (storing
  /// just a download URL here instead) is the recommended next step if
  /// that becomes an issue.
  Map<String, dynamic> toFirestore() {
    return {
      'hostId': hostId,
      'chargerId': chargerId,
      'label': label,
      'powerKw': powerKw,
      'ampere': ampere,
      'connector': connector.name,
      'city': city,
      'area': area,
      'chargingStandard': chargingStandard.name,
      'pricingModel': pricingModel.name,
      'price': price,
      'mapLink': mapLink,
      'latitude': latitude,
      'longitude': longitude,
      'residentsOnly': residentsOnly,
      'restrictedCommunity': restrictedCommunity,
      'photoBase64': photoBytes != null ? base64Encode(photoBytes!) : null,
      'freeSlots': freeSlots.map((s) => {
            'id': s.id,
            'chargerId': s.chargerId,
            'start': Timestamp.fromDate(s.start),
            'end': Timestamp.fromDate(s.end),
            'isBooked': s.isBooked,
            'recurrenceLabel': s.recurrenceLabel,
          }).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory ChargerProfile.fromFirestore(Map<String, dynamic> data) {
    final photoBase64 = data['photoBase64'] as String?;
    final rawSlots = (data['freeSlots'] as List?) ?? const [];

    return ChargerProfile(
      hostId: data['hostId'] as String,
      chargerId: data['chargerId'] as String,
      label: data['label'] as String,
      powerKw: (data['powerKw'] as num).toDouble(),
      ampere: (data['ampere'] as num).toDouble(),
      connector: ConnectorType.values.byName(data['connector'] as String),
      city: data['city'] as String,
      area: data['area'] as String,
      chargingStandard: ChargingStandard.values.byName(data['chargingStandard'] as String),
      pricingModel: PricingModel.values.byName(data['pricingModel'] as String),
      price: (data['price'] as num).toDouble(),
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      photoBytes: photoBase64 != null ? base64Decode(photoBase64) : null,
      mapLink: data['mapLink'] as String?,
      residentsOnly: data['residentsOnly'] as bool? ?? false,
      restrictedCommunity: data['restrictedCommunity'] as String?,
      freeSlots: rawSlots.map((raw) {
        final m = raw as Map<String, dynamic>;
        return AvailabilitySlot(
          id: m['id'] as String,
          chargerId: m['chargerId'] as String,
          start: (m['start'] as Timestamp).toDate(),
          end: (m['end'] as Timestamp).toDate(),
          isBooked: m['isBooked'] as bool? ?? false,
          recurrenceLabel: m['recurrenceLabel'] as String?,
        );
      }).toList(),
    );
  }
}
