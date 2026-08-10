enum BookingStatus {
  pendingWalletHold,
  pendingHostApproval,
  confirmed,
  inProgress,
  completed,
  declinedByHost,
  cancelledByDriver,
  cancelledByAdmin,
  expired,
}

enum TopUpStatus {
  pendingProofReview,
  approved,
  rejected,
}

enum PaymentMethod {
  instapay,
  vodafoneCash,
  other,
}

/// Physical connector shapes. NOTE: `gbtAc` and `gbtDc` exist because
/// China's GB/T standard uses its own distinct connector shapes (GB/T
/// 20234.2 for AC, GB/T 20234.3 for DC) that are physically incompatible
/// with Type 2 / CCS2, even though they can look superficially similar.
/// `type2` and `ccs` (CCS2/Combo) only ever belong to the European/
/// International standard - they can NEVER be paired with the Chinese
/// GB/T standard. See `ChargingStandardLabel.compatibleConnectors` below,
/// which enforces this at the UI level via a cascading dropdown.
enum ConnectorType { type1, type2, ccs, chademo, gbtAc, gbtDc }

extension ConnectorTypeLabel on ConnectorType {
  String get label => switch (this) {
        ConnectorType.type1 => 'Type 1 (J1772)',
        ConnectorType.type2 => 'Type 2 (Mennekes)',
        ConnectorType.ccs => 'CCS2 (Combo)',
        ConnectorType.chademo => 'CHAdeMO',
        ConnectorType.gbtAc => 'GB/T AC',
        ConnectorType.gbtDc => 'GB/T DC',
      };
}

enum PricingModel {
  perMinute,
  perKwh,
}

enum UserRole {
  driver,
  host,
  admin,
}

/// Broad EV charging ECOSYSTEM/STANDARD - distinct from the physical
/// `ConnectorType` above, but the two are NOT independent: only certain
/// connector shapes are physically possible under each standard (see
/// `compatibleConnectors` below). A car and a charger must share the SAME
/// ChargingStandard (and therefore a connector from the same bucket) to
/// actually be usable together.
enum ChargingStandard { chineseGbT, europeanCcs2 }

extension ChargingStandardLabel on ChargingStandard {
  String get label => switch (this) {
        ChargingStandard.chineseGbT => 'Chinese (GB/T)',
        ChargingStandard.europeanCcs2 => 'European (CCS2 / Type 2)',
      };

  String get shortLabel => switch (this) {
        ChargingStandard.chineseGbT => 'GB/T',
        ChargingStandard.europeanCcs2 => 'CCS2/Type2',
      };

  /// The ONLY physical connector types that are valid under this charging
  /// standard. Drives a cascading Charging Standard -> Connector Type
  /// dropdown (mirroring the Brand -> Model cascade for cars) so it is
  /// impossible to select a nonsensical combination like "Type 2" with
  /// "Chinese (GB/T)".
  List<ConnectorType> get compatibleConnectors => switch (this) {
        ChargingStandard.chineseGbT => const [ConnectorType.gbtAc, ConnectorType.gbtDc],
        ChargingStandard.europeanCcs2 => const [ConnectorType.type2, ConnectorType.ccs, ConnectorType.chademo, ConnectorType.type1],
      };
}

/// Days of the week, used for recurring weekly availability slots.
enum Weekday { sunday, monday, tuesday, wednesday, thursday, friday, saturday }

extension WeekdayLabel on Weekday {
  String get shortLabel => switch (this) {
        Weekday.sunday => 'Sun',
        Weekday.monday => 'Mon',
        Weekday.tuesday => 'Tue',
        Weekday.wednesday => 'Wed',
        Weekday.thursday => 'Thu',
        Weekday.friday => 'Fri',
        Weekday.saturday => 'Sat',
      };

  /// Dart's DateTime.weekday is 1=Monday..7=Sunday. This maps our enum to
  /// that numbering for date arithmetic.
  int get dartWeekday => switch (this) {
        Weekday.monday => DateTime.monday,
        Weekday.tuesday => DateTime.tuesday,
        Weekday.wednesday => DateTime.wednesday,
        Weekday.thursday => DateTime.thursday,
        Weekday.friday => DateTime.friday,
        Weekday.saturday => DateTime.saturday,
        Weekday.sunday => DateTime.sunday,
      };
}
