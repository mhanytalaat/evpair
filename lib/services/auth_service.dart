import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key used to persist the signed-in user's email locally so the session
/// survives an app/browser restart until the user explicitly signs out.
const String _kSessionEmailPrefKey = 'evpair_session_email';

class AuthService extends ChangeNotifier {
  final FirebaseFirestore _db;

  AuthService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  bool isRegistered = false;
  bool isLoadingProfile = false;

  /// True while we're checking for a previously saved session on app start.
  bool isInitializing = true;

  String? firstName;
  String? lastName;
  String? email;
  String? phone;

  String get fullName => [firstName, lastName]
      .where((s) => s != null && s.trim().isNotEmpty)
      .join(' ');

  String get displayName => fullName.isNotEmpty ? fullName : 'Guest user';

  String get initials {
    final first = (firstName ?? '').trim();
    final last = (lastName ?? '').trim();
    final a = first.isNotEmpty ? first[0] : '';
    final b = last.isNotEmpty ? last[0] : '';
    final result = '$a$b'.toUpperCase();
    return result.isEmpty ? 'EV' : result;
  }

  String? get userDocId {
    final value = email?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    return value.replaceAll(RegExp(r'[^a-z0-9@._-]'), '_');
  }

  Map<String, dynamic> toFirestore() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'profileInitials': initials,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdFrom': 'evpair_flutter_ui',
    };
  }

  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
  }) async {
    this.firstName = firstName.trim();
    this.lastName = lastName.trim();
    this.email = email.trim().toLowerCase();
    this.phone = phone.trim();
    isRegistered = true;
    notifyListeners();

    await saveProfileToFirestore();
    await _persistSession(this.email!);
  }

  /// Signs an existing user in by email. Returns true if a matching
  /// Firestore profile was found and loaded, false otherwise.
  Future<bool> signIn(String emailAddress) async {
    final id = _docIdFor(emailAddress);
    if (id == null) return false;

    isLoadingProfile = true;
    notifyListeners();

    final doc = await _db.collection('users').doc(id).get();
    final data = doc.data();
    isLoadingProfile = false;

    if (data == null) {
      notifyListeners();
      return false;
    }

    firstName = data['firstName'] as String?;
    lastName = data['lastName'] as String?;
    email = data['email'] as String?;
    phone = data['phone'] as String?;
    isRegistered = true;
    notifyListeners();

    await _persistSession(email ?? emailAddress);
    return true;
  }

  /// Signs the current user out and forgets the persisted session.
  Future<void> signOut() async {
    firstName = null;
    lastName = null;
    email = null;
    phone = null;
    isRegistered = false;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionEmailPrefKey);
  }

  /// Call once on app start to restore a previously signed-in session.
  Future<void> tryAutoSignIn() async {
    isInitializing = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString(_kSessionEmailPrefKey);

    if (savedEmail != null && savedEmail.trim().isNotEmpty) {
      await loadProfileFromFirestore(savedEmail);
    }

    isInitializing = false;
    notifyListeners();
  }

  Future<void> _persistSession(String emailAddress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessionEmailPrefKey, emailAddress.trim().toLowerCase());
  }

  String? _docIdFor(String emailAddress) {
    final value = emailAddress.trim().toLowerCase();
    if (value.isEmpty || !value.contains('@')) return null;
    return value.replaceAll(RegExp(r'[^a-z0-9@._-]'), '_');
  }

  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
  }) async {
    await register(
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
    );
  }

  Future<void> saveProfileToFirestore() async {
    final id = userDocId;
    if (id == null) return;

    await _db.collection('users').doc(id).set(
      toFirestore(),
      SetOptions(merge: true),
    );
  }

  Future<void> loadProfileFromFirestore(String emailAddress) async {
    final id = emailAddress.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9@._-]'), '_');
    if (id.isEmpty) return;

    isLoadingProfile = true;
    notifyListeners();

    final doc = await _db.collection('users').doc(id).get();
    final data = doc.data();

    if (data != null) {
      firstName = data['firstName'] as String?;
      lastName = data['lastName'] as String?;
      email = data['email'] as String?;
      phone = data['phone'] as String?;
      isRegistered = true;
    }

    isLoadingProfile = false;
    notifyListeners();
  }
}
