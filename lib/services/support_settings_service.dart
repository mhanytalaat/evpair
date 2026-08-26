import 'package:cloud_firestore/cloud_firestore.dart';

/// EVPair's support contact details - email, phone, and WhatsApp number.
/// Deliberately NOT hardcoded: it's read live from Firestore at
/// `appSettings/support`, so you can update any of these values from the
/// Firebase console at any time with no app update required.
class SupportSettings {
  final String? email;
  final String? phone; // shown as-is, used for tel: links
  final String? whatsapp; // digits only, international format e.g. "201001234567" (no + or spaces)

  const SupportSettings({this.email, this.phone, this.whatsapp});

  static const empty = SupportSettings();

  bool get hasAnyContact =>
      (email?.trim().isNotEmpty ?? false) || (phone?.trim().isNotEmpty ?? false) || (whatsapp?.trim().isNotEmpty ?? false);

  factory SupportSettings.fromMap(Map<String, dynamic>? data) {
    if (data == null) return empty;
    return SupportSettings(
      email: data['email'] as String?,
      phone: data['phone'] as String?,
      whatsapp: data['whatsapp'] as String?,
    );
  }
}

class SupportSettingsService {
  SupportSettingsService._();

  static Stream<SupportSettings> watch() {
    return FirebaseFirestore.instance
        .collection('appSettings')
        .doc('support')
        .snapshots()
        .map((snap) => SupportSettings.fromMap(snap.data()));
  }
}
