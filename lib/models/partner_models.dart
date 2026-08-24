import 'package:cloud_firestore/cloud_firestore.dart';

/// Status flow for a home-installation/service request:
///   open        - submitted by a driver, waiting for any partner to
///                 accept it (a simple first-come pool, not manual
///                 admin assignment - keeps this MVP simple since there
///                 can be multiple partners).
///   accepted    - a partner has claimed it and is scheduling/visiting.
///   completed   - the partner marked the job done.
///   cancelled   - the driver cancelled before a partner accepted, or an
///                 admin cancelled it.
enum InstallRequestStatus { open, accepted, completed, cancelled }

/// What kind of partner service is being requested. Lets partners filter
/// the open-jobs pool to only what they actually do (e.g. a cable-only
/// partner doesn't need to scroll past station installs), and lets you
/// report on demand by category later.
enum ServiceCategory { station, adaptor, cable, maintenance, other }

extension ServiceCategoryLabel on ServiceCategory {
  String get label {
    switch (this) {
      case ServiceCategory.station:
        return 'Home Charging Station';
      case ServiceCategory.adaptor:
        return 'Adaptor';
      case ServiceCategory.cable:
        return 'Cable';
      case ServiceCategory.maintenance:
        return 'Maintenance / Repair';
      case ServiceCategory.other:
        return 'Other';
    }
  }

  String get shortLabel {
    switch (this) {
      case ServiceCategory.station:
        return 'Station';
      case ServiceCategory.adaptor:
        return 'Adaptor';
      case ServiceCategory.cable:
        return 'Cable';
      case ServiceCategory.maintenance:
        return 'Maintenance';
      case ServiceCategory.other:
        return 'Other';
    }
  }

  String get description {
    switch (this) {
      case ServiceCategory.station:
        return 'New home charging station install or relocation';
      case ServiceCategory.adaptor:
        return 'Sourcing or installing a connector/standard adaptor';
      case ServiceCategory.cable:
        return 'New, longer, or replacement charging cable';
      case ServiceCategory.maintenance:
        return 'Repair or troubleshooting for an existing station';
      case ServiceCategory.other:
        return 'Anything else - describe it in the notes';
    }
  }
}

/// A driver's request for a home-related EV service: a new station
/// install, an adaptor, a cable, maintenance on an existing station, or
/// anything else (see ServiceCategory). Despite the class name
/// (kept for backward compatibility with existing Firestore data /
/// screen names), this now represents ANY category, not only station
/// installs.
class InstallationRequest {
  final String id;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final ServiceCategory category;
  final String city;
  final String area;
  final String addressDetails;
  final String? notes;
  final DateTime createdAt;

  InstallRequestStatus status;
  String? partnerId;
  String? partnerName;
  DateTime? acceptedAt;
  DateTime? completedAt;
  String? completionNotes;

  InstallationRequest({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.category,
    required this.city,
    required this.area,
    required this.addressDetails,
    this.notes,
    DateTime? createdAt,
    this.status = InstallRequestStatus.open,
    this.partnerId,
    this.partnerName,
    this.acceptedAt,
    this.completedAt,
    this.completionNotes,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toFirestore() {
    return {
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'category': category.name,
      'city': city,
      'area': area,
      'addressDetails': addressDetails,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status.name,
      'partnerId': partnerId,
      'partnerName': partnerName,
      'acceptedAt': acceptedAt == null ? null : Timestamp.fromDate(acceptedAt!),
      'completedAt': completedAt == null ? null : Timestamp.fromDate(completedAt!),
      'completionNotes': completionNotes,
    };
  }

  factory InstallationRequest.fromFirestore(String id, Map<String, dynamic> data) {
    final created = data['createdAt'];
    final accepted = data['acceptedAt'];
    final completed = data['completedAt'];
    return InstallationRequest(
      id: id,
      driverId: data['driverId'] as String? ?? '',
      driverName: data['driverName'] as String? ?? '',
      driverPhone: data['driverPhone'] as String? ?? '',
      category: ServiceCategory.values.firstWhere(
        (c) => c.name == data['category'],
        // Older documents saved before the category field existed
        // default to "station" since that was the only type of
        // request the app could create at the time.
        orElse: () => ServiceCategory.station,
      ),
      city: data['city'] as String? ?? '',
      area: data['area'] as String? ?? '',
      addressDetails: data['addressDetails'] as String? ?? '',
      notes: data['notes'] as String?,
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
      status: InstallRequestStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => InstallRequestStatus.open,
      ),
      partnerId: data['partnerId'] as String?,
      partnerName: data['partnerName'] as String?,
      acceptedAt: accepted is Timestamp ? accepted.toDate() : null,
      completedAt: completed is Timestamp ? completed.toDate() : null,
      completionNotes: data['completionNotes'] as String?,
    );
  }
}

/// Equipment catalog item type. Kept intentionally aligned with
/// ServiceCategory (minus "maintenance", which is a service, not a
/// product) so the two systems report consistently.
enum EquipmentType { chargingCable, adaptor, homeChargingStation, other }

extension EquipmentTypeLabel on EquipmentType {
  String get label {
    switch (this) {
      case EquipmentType.chargingCable:
        return 'Charging Cable';
      case EquipmentType.adaptor:
        return 'Adaptor';
      case EquipmentType.homeChargingStation:
        return 'Home Charging Station';
      case EquipmentType.other:
        return 'Other';
    }
  }

  String get shortLabel {
    switch (this) {
      case EquipmentType.chargingCable:
        return 'Cable';
      case EquipmentType.adaptor:
        return 'Adaptor';
      case EquipmentType.homeChargingStation:
        return 'Station';
      case EquipmentType.other:
        return 'Other';
    }
  }

  /// Maps an equipment catalog type to the matching service request
  /// category, so both systems (catalog + service requests) report
  /// consistently under the same category labels.
  ServiceCategory get asServiceCategory {
    switch (this) {
      case EquipmentType.chargingCable:
        return ServiceCategory.cable;
      case EquipmentType.adaptor:
        return ServiceCategory.adaptor;
      case EquipmentType.homeChargingStation:
        return ServiceCategory.station;
      case EquipmentType.other:
        return ServiceCategory.other;
    }
  }
}

enum EquipmentMode { borrow, buy }

/// Who is actually selling/lending an equipment listing. This is
/// separate from "who is a registered EVPair partner" - a listing can
/// be posted under a MANUFACTURER/BRAND name (e.g. "PowerX") that you
/// (admin) list on their behalf without that brand having its own
/// partner login, alongside listings posted by an actual registered
/// installPartner, or by EVPair's own stock.
enum EquipmentOwnerType { partner, brand, platform }

extension EquipmentOwnerTypeLabel on EquipmentOwnerType {
  String get label {
    switch (this) {
      case EquipmentOwnerType.partner:
        return 'Partner';
      case EquipmentOwnerType.brand:
        return 'Brand';
      case EquipmentOwnerType.platform:
        return 'EVPair';
    }
  }
}

/// A single catalog item a partner, a brand (e.g. "PowerX"), or EVPair
/// itself makes available - e.g. "Type 2 to GB/T adaptor - borrow for
/// 200 EGP deposit" or "PowerX 7kW home charging station - buy for
/// 18,000 EGP".
class EquipmentListing {
  final String id;
  final String ownerId; // partnerId, a brand slug (e.g. "powerx"), or kPlatformOwnerId
  final String ownerName; // display name, e.g. "PowerX", "Ahmed's Installation Services", "EVPair"
  final EquipmentOwnerType ownerType;
  final EquipmentType type;
  final String title;
  final String description;
  final EquipmentMode mode;
  final double price; // purchase price, or deposit amount when mode == borrow
  final bool available;

  /// Public download URL for the item's photo (e.g. a Firebase Storage
  /// download URL, or any public image URL). Null/empty means no photo
  /// was set yet - the UI falls back to a category icon in that case,
  /// so this field is optional and won't break existing listings.
  final String? imageUrl;

  EquipmentListing({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.ownerType,
    required this.type,
    required this.title,
    required this.description,
    required this.mode,
    required this.price,
    this.available = true,
    this.imageUrl,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'ownerId': ownerId,
      'ownerName': ownerName,
      'ownerType': ownerType.name,
      'type': type.name,
      'title': title,
      'description': description,
      'mode': mode.name,
      'price': price,
      'available': available,
      'imageUrl': imageUrl,
    };
  }

  factory EquipmentListing.fromFirestore(String id, Map<String, dynamic> data) {
    final ownerId = data['ownerId'] as String? ?? '';
    return EquipmentListing(
      id: id,
      ownerId: ownerId,
      ownerName: data['ownerName'] as String? ?? 'EVPair',
      ownerType: EquipmentOwnerType.values.firstWhere(
        (t) => t.name == data['ownerType'],
        // Older documents saved before ownerType existed: infer
        // platform stock from the special owner id, otherwise assume
        // a regular partner listing.
        orElse: () => ownerId == kPlatformOwnerId ? EquipmentOwnerType.platform : EquipmentOwnerType.partner,
      ),
      type: EquipmentType.values.firstWhere(
        (t) => t.name == data['type'],
        orElse: () => EquipmentType.chargingCable,
      ),
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      mode: EquipmentMode.values.firstWhere(
        (m) => m.name == data['mode'],
        orElse: () => EquipmentMode.buy,
      ),
      price: (data['price'] as num?)?.toDouble() ?? 0,
      available: data['available'] as bool? ?? true,
      // Missing/empty on older documents - fine, UI treats null the
      // same as "no photo uploaded yet".
      imageUrl: (data['imageUrl'] as String?)?.trim().isEmpty == true ? null : data['imageUrl'] as String?,
    );
  }
}

enum EquipmentRequestStatus { pending, approved, fulfilled, returned, cancelled }

/// A driver's request to borrow or buy a specific EquipmentListing.
class EquipmentRequest {
  final String id;
  final String listingId;
  final String listingTitle;
  final EquipmentMode mode;
  final double price;
  final String driverId;
  final String driverName;
  final DateTime requestedAt;

  EquipmentRequestStatus status;
  DateTime? returnedAt;

  EquipmentRequest({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.mode,
    required this.price,
    required this.driverId,
    required this.driverName,
    DateTime? requestedAt,
    this.status = EquipmentRequestStatus.pending,
    this.returnedAt,
  }) : requestedAt = requestedAt ?? DateTime.now();

  Map<String, dynamic> toFirestore() {
    return {
      'listingId': listingId,
      'listingTitle': listingTitle,
      'mode': mode.name,
      'price': price,
      'driverId': driverId,
      'driverName': driverName,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'status': status.name,
      'returnedAt': returnedAt == null ? null : Timestamp.fromDate(returnedAt!),
    };
  }

  factory EquipmentRequest.fromFirestore(String id, Map<String, dynamic> data) {
    final requested = data['requestedAt'];
    final returned = data['returnedAt'];
    return EquipmentRequest(
      id: id,
      listingId: data['listingId'] as String? ?? '',
      listingTitle: data['listingTitle'] as String? ?? '',
      mode: EquipmentMode.values.firstWhere(
        (m) => m.name == data['mode'],
        orElse: () => EquipmentMode.buy,
      ),
      price: (data['price'] as num?)?.toDouble() ?? 0,
      driverId: data['driverId'] as String? ?? '',
      driverName: data['driverName'] as String? ?? '',
      requestedAt: requested is Timestamp ? requested.toDate() : DateTime.now(),
      status: EquipmentRequestStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => EquipmentRequestStatus.pending,
      ),
      returnedAt: returned is Timestamp ? returned.toDate() : null,
    );
  }
}

/// Wallet user id used for equipment listings owned by EVPair itself
/// rather than by an individual partner (e.g. company-stocked adaptors).
const String kPlatformOwnerId = 'evpair_platform';
