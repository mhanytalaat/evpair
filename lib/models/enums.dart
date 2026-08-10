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

enum ConnectorType {
  type1,
  type2,
  ccs,
  chademo,
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
/// `ConnectorType` (Type 1 / Type 2 / CCS / CHAdeMO) above. Two chargers
/// can look similar but be wired for completely different regional
/// charging standards:
///   - Chinese-market and many Chinese-imported vehicles (Arcfox, several
///     BYD imports, etc.) use the Chinese national **GB/T** standard.
///   - Most European-market EVs (VW ID3/ID4, Geely models sold in Europe,
///     etc.) use **CCS2 / Type 2**.
/// A car and a charger must share the SAME ChargingStandard to actually be
/// usable together, regardless of whether their ConnectorType/ampere
/// happen to match on paper.
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
