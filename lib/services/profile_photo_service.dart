import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

/// Handles a user's profile photo, stored as a small base64-encoded
/// string directly on their `users/{uid}` Firestore document (field
/// `photoBase64`) - the same pattern already used for charger photos
/// elsewhere in the app (Image.memory + bytes) - rather than Firebase
/// Storage. This deliberately avoids Firebase Storage's download-URL +
/// CORS issue we already hit with equipment images on Flutter Web:
/// base64-in-Firestore works identically on web, iOS, and Android with
/// no extra CORS configuration.
///
/// Kept as a standalone service (not part of AuthService) so it can be
/// used from any screen without needing changes to auth_service.dart.
class ProfilePhotoService {
  ProfilePhotoService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final ImagePicker _picker = ImagePicker();

  /// Opens the camera or gallery, and if the user picks a photo, saves
  /// it (resized down via imageQuality/maxWidth to keep the Firestore
  /// document small) to `users/{uid}.photoBase64`. Returns true if a
  /// photo was saved, false if the user cancelled the picker.
  static Future<bool> pickAndSave(String uid, {required ImageSource source}) async {
    final file = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 512);
    if (file == null) return false;

    final bytes = await file.readAsBytes();
    final base64Photo = base64Encode(bytes);

    await _db.collection('users').doc(uid).set(
      {
        'photoBase64': base64Photo,
        'photoUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
  }

  static Future<void> removePhoto(String uid) async {
    await _db.collection('users').doc(uid).set(
      {'photoBase64': null},
      SetOptions(merge: true),
    );
  }

  /// Live stream of this user's current photo bytes, or null if they
  /// haven't set one. Use with StreamBuilder wherever an avatar is shown
  /// (Profile screen header, footer avatar icon, etc.).
  static Stream<Uint8List?> watch(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      final b64 = snap.data()?['photoBase64'] as String?;
      if (b64 == null || b64.isEmpty) return null;
      try {
        return base64Decode(b64);
      } catch (_) {
        return null;
      }
    });
  }
}
