import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// NEW (9/24 update - "percentage to be taken to the app 7%, let us
/// make on firebase, i will make it free of charge for now"): the
/// platform commission rate taken from each completed charging
/// session's payout (see services/wallet_service.dart's
/// createPayoutRequest / settleBookingWithPendingPayout, and
/// services/booking_service.dart's completeSession) previously always
/// used a hardcoded 10% default with no way to change it without a new
/// app release. It's now read LIVE from a single Firestore document at
/// `appSettings/commission` (field: `rate`, a decimal fraction - e.g.
/// 0.07 for 7%, 0 for free/no commission).
///
/// On the very FIRST run ever (the document doesn't exist), this seeds
/// Firestore with the DESIGNED rate of 0.07 (7%) - matching the rate
/// you specified. To make sessions free of any commission for now (as
/// you said you'd do yourself), simply open:
///
///   Firestore Console -> appSettings -> commission -> set `rate` to 0
///
/// Every host's payout will then be calculated with 0% commission
/// (100% of the session cost) instantly, with no app update needed.
/// Change it back to 0.07 (or any other value) whenever you're ready to
/// start taking a cut - the change takes effect live, no app restart
/// needed, because this listens for updates the whole time the app is
/// open.
///
/// Call `hydrate()` once during app startup (see
/// screens/system/app_bootstrap.dart), before BookingService needs to
/// read `.rate` - same pattern already used for LocationsService,
/// PowerOptionsService, and CarModelsService.
class CommissionService extends ChangeNotifier {
  CommissionService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const _docPath = 'appSettings';
  static const _docId = 'commission';

  /// Designed default commission rate (7%) - used only to seed
  /// Firestore on the very first run. Has NO effect after that; the
  /// live Firestore value always wins from then on.
  static const double kDesignedDefaultRate = 0.07;

  bool isLoading = true;
  double _rate = kDesignedDefaultRate;

  /// The LIVE commission rate as a decimal fraction (e.g. 0.07 = 7%,
  /// 0 = free/no commission). This is what
  /// BookingService.completeSession() actually uses for every payout
  /// calculation.
  double get rate => _rate;

  Future<void> hydrate() async {
    isLoading = true;
    notifyListeners();
    try {
      final doc = await _db.collection(_docPath).doc(_docId).get();
      if (!doc.exists || doc.data()?['rate'] == null) {
        await _seedDefault();
        _rate = kDesignedDefaultRate;
      } else {
        _rate = (doc.data()!['rate'] as num).toDouble();
      }
      // Stay live for the rest of the app session - if you change the
      // rate in the Firebase console while the app is open, it updates
      // immediately with no restart needed, exactly like
      // WalletService's live balance listener.
      _db.collection(_docPath).doc(_docId).snapshots().listen((snap) {
        final value = snap.data()?['rate'];
        if (value is num) {
          _rate = value.toDouble();
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('CommissionService.hydrate failed, falling back to $kDesignedDefaultRate: $e');
      _rate = kDesignedDefaultRate;
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> _seedDefault() async {
    await _db.collection(_docPath).doc(_docId).set({'rate': kDesignedDefaultRate});
  }
}
