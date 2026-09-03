/// Validates and formats Egyptian vehicle plate numbers.
///
/// Egyptian plates are NUMBERS FIRST, then LETTERS. The exact shape
/// depends on the governorate that issued the plate:
///
///   - Cairo              : 3 digits + 3 letters   (e.g. "123-ABC")
///   - Giza                : 4 digits + 2 letters   (e.g. "1234-AB")
///   - Other governorates  : 4 digits + 3 letters   (e.g. "1234-ABC"),
///                           where the first letter typically encodes the
///                           specific governorate.
///
/// Since a driver's registration governorate isn't necessarily tracked
/// separately in the car profile, this validator accepts the UNION of
/// all three shapes rather than requiring the user to pick a region
/// first - simpler UX, and still rejects anything that isn't a real
/// Egyptian plate shape. Both Latin letters (for transliterated/English
/// entry) and Arabic letters (ا ب ج ...) are accepted, since drivers may
/// type either depending on their keyboard - though the segmented input
/// widget (see widgets/plate_number_field.dart) forces English letters
/// specifically, per product requirement.
class PlateNumberValidator {
  PlateNumberValidator._();

  static const String _lettersClass = r'A-Za-z\u0621-\u064A';

  // 3 digits + 3 letters (Cairo), OR 4 digits + 2 letters (Giza), OR
  // 4 digits + 3 letters (other governorates).
  static final RegExp _validShapes = RegExp(
    '^(\\d{3}[$_lettersClass]{3}|\\d{4}[$_lettersClass]{2}|\\d{4}[$_lettersClass]{3})\$',
  );

  /// Returns null when valid, otherwise a user-facing error message.
  /// Use directly as a TextFormField `validator`.
  static String? validate(String? raw) {
    final value = _strip(raw);
    if (value.isEmpty) return 'Enter the plate number';
    if (!_validShapes.hasMatch(value)) {
      return 'Use digits then letters - e.g. 123-ABC (Cairo), 1234-AB (Giza), or 1234-ABC (other governorates)';
    }
    return null;
  }

  static bool isValid(String? raw) => validate(raw) == null;

  /// Normalizes input for storage/display: strips spaces/dashes and
  /// uppercases Latin letters, while leaving Arabic letters untouched.
  static String normalize(String raw) => _strip(raw).toUpperCase();

  static String _strip(String? raw) => (raw ?? '').trim().replaceAll(' ', '').replaceAll('-', '');

  /// Splits an already-valid plate into its digit prefix and letter
  /// suffix, useful for display like "1234 · AB", and for pre-filling
  /// the segmented PlateNumberField widget when editing an existing car.
  static ({String digits, String letters})? split(String raw) {
    final value = normalize(raw);
    if (!isValid(value)) return null;
    final match = RegExp('^(\\d+)([$_lettersClass]+)\$').firstMatch(value);
    if (match == null) return null;
    return (digits: match.group(1)!, letters: match.group(2)!);
  }

  /// Combines a digits string and a letters string (as typed into the
  /// segmented PlateNumberField widget) back into the single normalized
  /// plate string used everywhere else in the app (CarProfile.plateNumber,
  /// Booking.carPlateNumber, etc.). Blank/partial input is combined as-is
  /// (without validation) so the caller can still show a live preview
  /// while the user is mid-typing - validate the RESULT with validate()
  /// before actually submitting.
  static String combine({required String digits, required String letters}) {
    return '${digits.trim()}${letters.trim()}'.toUpperCase();
  }
}
