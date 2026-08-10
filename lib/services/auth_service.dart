import 'package:flutter/foundation.dart';

/// Minimal in-memory registration state. Users must register before they
/// can add/manage a charging station (host action) or book a charging
/// station (driver action) - browsing does NOT require registration.
class AuthService extends ChangeNotifier {
  bool isRegistered = false;
  String? firstName;
  String? lastName;
  String? email;
  String? phone;

  String get fullName => [firstName, lastName].where((s) => s != null && s.isNotEmpty).join(' ');

  void register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
  }) {
    this.firstName = firstName;
    this.lastName = lastName;
    this.email = email;
    this.phone = phone;
    isRegistered = true;
    notifyListeners();
  }
}
