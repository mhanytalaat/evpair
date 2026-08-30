/// Fixes the "two zeros" problem: a country code already replaces the
/// local trunk prefix (the leading 0 in "01XXXXXXXXX"), so simply
/// concatenating `countryCode + rawInput` produced numbers like
/// "+2001XXXXXXXXX" (country code, then a redundant 0, then the real
/// number). Drivers/hosts still TYPE their number the normal Egyptian way
/// (starting with 0, e.g. "01001234567") since that's what they're used
/// to - this helper strips that leading 0 only at the point the number is
/// combined with the country code for storage, and adds it back when
/// re-displaying a stored number for editing (see AccountSettingsScreen).
class PhoneNumberValidator {
  PhoneNumberValidator._();

  /// Removes a single leading trunk-prefix zero, if present (e.g.
  /// "01001234567" -> "1001234567"). Only strips ONE leading zero -
  /// numbers don't have two.
  static String stripLeadingZero(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('0')) return trimmed.substring(1);
    return trimmed;
  }

  /// Adds the leading 0 back for display/editing, e.g. when loading a
  /// previously-saved Egyptian number back into a text field.
  static String addLeadingZeroIfMissing(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || trimmed.startsWith('0')) return trimmed;
    return '0$trimmed';
  }

  /// Validates what the user TYPED (still including the leading 0 for
  /// Egypt). Returns null when valid, otherwise a user-facing message.
  static String? validate(String? raw, {required String countryCode}) {
    if (raw == null || raw.trim().isEmpty) return 'Enter your mobile number';
    final stripped = stripLeadingZero(raw);
    if (countryCode == '+20') {
      // Egyptian mobile numbers are 11 digits as typed (0 + 10 digits),
      // i.e. 10 digits once the leading 0 is removed.
      if (!RegExp(r'^\d{10}$').hasMatch(stripped)) {
        return 'Enter a valid number, e.g. 01001234567';
      }
    } else {
      if (!RegExp(r'^\d{6,12}$').hasMatch(stripped)) {
        return 'Enter a valid mobile number';
      }
    }
    return null;
  }

  /// Combines the country code with the typed local number for storage,
  /// stripping the redundant leading 0 - e.g. countryCode "+20" + typed
  /// "01001234567" -> "+201001234567" (NOT "+2001001234567").
  static String toE164(String raw, {required String countryCode}) {
    return '$countryCode${stripLeadingZero(raw)}';
  }
}
