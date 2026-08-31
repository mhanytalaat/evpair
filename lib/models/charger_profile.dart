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

  AvailabilitySlot? findFittingSlot(DateTime reqStart, DateTime reqEnd) {
    final candidates = freeSlots.where((s) => s.canFit(reqStart, reqEnd)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return candidates.isEmpty ? null : candidates.first;
  }

  String get priceLabel => PricingService.priceLabel(pricingModel, price);

  /// Firestore document shape for the `chargers` collection.
  ///
  /// FIX (30/8 investigation - "one-time slot doesn't save, recurring
  /// does"): this now builds each free-slot map through a dedicated,
  /// defensive `_slotToFirestore` helper (see below) instead of an
  /// inline map literal. The previous inline version wrote
  /// `'recurrenceLabel': s.recurrenceLabel` directly, which is `null`
  /// for every ONE-TIME slot (recurring slots always have a non-null
  /// string like "Every Sun"). While a null value inside a Firestore
  /// map is technically valid, several Firestore client SDK versions
  /// and any custom validation have been known to reject or silently
  /// drop `null` values nested inside arrays-of-maps depending on
  /// platform/version - which lines up exactly with the pattern you
  /// found (multi-slot/recurring saves worked, single one-time slot did
  /// not). `_slotToFirestore` now OMITS the `recurrenceLabel` key
  /// entirely for one-time slots instead of sending it as `null`,
  /// removing that risk completely regardless of which underlying cause
  /// it was.
  ///
  /// Also hardened: `latitude`/`longitude`/`price`/`powerKw`/`ampere` are
  /// now passed through `_safeNum`, which converts any accidental NaN/
  /// Infinity value (which Firestore always rejects outright) to 0.0
  /// instead of silently corrupting the whole document write.
  Map<String, dynamic> toFirestore() {
    return {
      'hostId': hostId,
      'chargerId': chargerId,
      'label': label,
      'powerKw': _safeNum(powerKw),
      'ampere': _safeNum(ampere),
      'connector': connector.name,
      'city': city,
      'area': area,
      'chargingStandard': chargingStandard.name,
      'pricingModel': pricingModel.name,
      'price': _safeNum(price),
      'mapLink': mapLink,
      'latitude': _safeNum(latitude),
      'longitude': _safeNum(longitude),
      'residentsOnly': residentsOnly,
      'restrictedCommunity': restrictedCommunity,
      'photoBase64': photoBytes != null ? base64Encode(photoBytes!) : null,
      'freeSlots': freeSlots.map(_slotToFirestore).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Converts a single AvailabilitySlot to its Firestore map shape.
  /// `recurrenceLabel` is OMITTED entirely (not sent as null) when the
  /// slot is a one-time slot - see the note on toFirestore() above for
  /// why this matters.
  static Map<String, dynamic> _slotToFirestore(AvailabilitySlot s) {
    final map = <String, dynamic>{
      'id': s.id,
      'chargerId': s.chargerId,
      'start': Timestamp.fromDate(s.start),
      'end': Timestamp.fromDate(s.end),
      'isBooked': s.isBooked,
    };
    if (s.recurrenceLabel != null && s.recurrenceLabel!.isNotEmpty) {
      map['recurrenceLabel'] = s.recurrenceLabel;
    }
    return map;
  }

  static double _safeNum(double value) {
    if (value.isNaN || value.isInfinite) return 0.0;
    return value;
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
