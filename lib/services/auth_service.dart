import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// The only email allowed to see/use the Admin tab. Change this if the
/// admin account changes.
const String kAdminEmail = 'mhany@outlook.com';

/// Handles real account creation/sign-in via Firebase Authentication
/// (email + password), and keeps a matching profile document in the
/// Firestore `users` collection (keyed by the Firebase Auth uid) with the
/// extra fields the UI needs (firstName, lastName, phone).
class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  bool isRegistered = false;
  bool isLoadingProfile = false;

  /// True while we're checking Firebase Auth's persisted session on app
  /// start. Screens can use this to show a brief loading state instead of
  /// flashing "guest" UI before the session is restored.
  bool isInitializing = true;

  String? uid;
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

  /// Only true when signed in with the designated admin account. Used to
  /// hide the Admin tab from every other user.
  bool get isAdmin => (email ?? '').trim().toLowerCase() == kAdminEmail;

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'profileInitials': initials,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdFrom': 'evpair_flutter_ui',
    };
  }

  /// Creates a brand-new Firebase Auth account (email + password) and a
  /// matching Firestore profile document keyed by the new uid. Throws a
  /// [FirebaseAuthException] on failure (e.g. email-already-in-use,
  /// weak-password) - the caller (RegisterScreen) shows the message.
  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    uid = credential.user!.uid;
    this.firstName = firstName.trim();
    this.lastName = lastName.trim();
    this.email = email.trim().toLowerCase();
    this.phone = phone.trim();
    isRegistered = true;
    notifyListeners();

    await saveProfileToFirestore();
  }

  /// Signs an existing user in with email + password via Firebase Auth,
  /// then loads their extra profile fields from Firestore. Throws a
  /// [FirebaseAuthException] on failure (e.g. wrong-password,
  /// user-not-found) - the caller (SignInScreen) shows the message.
  Future<void> signIn(String emailAddress, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: emailAddress.trim(),
      password: password,
    );
    await _loadProfileForUid(credential.user!.uid, fallbackEmail: emailAddress.trim());
  }

  /// Signs the current user out of Firebase Auth. Firebase Auth clears its
  /// own persisted session automatically - no manual storage cleanup
  /// needed here.
  Future<void> signOut() async {
    await _auth.signOut();
    _clearLocalProfile();
    notifyListeners();
  }

  /// Call once on app start. Firebase Auth persists sessions natively, so
  /// this just checks `currentUser` and loads their Firestore profile if
  /// one is already signed in.
  Future<void> tryAutoSignIn() async {
    isInitializing = true;
    notifyListeners();

    final current = _auth.currentUser;
    if (current != null) {
      await _loadProfileForUid(current.uid, fallbackEmail: current.email);
    }

    isInitializing = false;
    notifyListeners();
  }

  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    this.firstName = firstName.trim();
    this.lastName = lastName.trim();
    this.phone = phone.trim();
    notifyListeners();
    await saveProfileToFirestore();
  }

  Future<void> saveProfileToFirestore() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).set(
      toFirestore(),
      SetOptions(merge: true),
    );
  }

  Future<void> _loadProfileForUid(String userId, {String? fallbackEmail}) async {
    isLoadingProfile = true;
    notifyListeners();

    uid = userId;
    final doc = await _db.collection('users').doc(userId).get();
    final data = doc.data();

    if (data != null) {
      firstName = data['firstName'] as String?;
      lastName = data['lastName'] as String?;
      email = (data['email'] as String?) ?? fallbackEmail;
      phone = data['phone'] as String?;
    } else {
      email = fallbackEmail;
    }
    isRegistered = true;

    isLoadingProfile = false;
    notifyListeners();
  }

  void _clearLocalProfile() {
    uid = null;
    firstName = null;
    lastName = null;
    email = null;
    phone = null;
    isRegistered = false;
  }

  /// Converts a raw [FirebaseAuthException] code into a short, readable
  /// message suitable for showing directly under a form field.
  static String messageForAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account already exists for this email. Try signing in instead.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'user-not-found':
        return 'No account found with this email. Please register instead.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
}
