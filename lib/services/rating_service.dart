import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/rating.dart';

/// Handles post-booking ratings: a driver rating the host they charged
/// with, and a host rating the driver who used their station. Both
/// directions use the exact same Rating model/collection, distinguished
/// only by `raterRole`.
class RatingService extends ChangeNotifier {
  RatingService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final _uuid = const Uuid();

  // bookingId -> set of RaterRole names who have already rated this
  // booking, from the current user's perspective (only ever contains
  // entries for ratings THIS signed-in user submitted, loaded in
  // hydrate() below). Used to hide the "Rate your experience" prompt
  // once already submitted, without needing a network round-trip on
  // every screen build.
  final Map<String, Set<String>> _myRatedBookings = {};

  // Cache of fetched summaries so re-opening the same charger/driver
  // profile repeatedly doesn't re-query every time within a session.
  final Map<String, RatingSummary> _summaryCache = {};

  /// Loads which bookings the signed-in user has already rated, so the
  /// "Rate your experience" prompt can be hidden correctly as soon as
  /// the app starts, not just after submitting a rating in this session.
  Future<void> hydrate(String userId) async {
    try {
      final snap = await _db.collection('ratings').where('raterId', isEqualTo: userId).get();
      _myRatedBookings.clear();
      for (final doc in snap.docs) {
        final data = doc.data();
        final bookingId = data['bookingId'] as String? ?? '';
        final raterRole = data['raterRole'] as String? ?? '';
        _myRatedBookings.putIfAbsent(bookingId, () => {}).add(raterRole);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('RatingService.hydrate failed: $e');
    }
  }

  /// Whether the signed-in user (in the given role) has already rated
  /// this booking - use this to decide whether to show the "Rate your
  /// experience" card/button.
  bool hasRatedBooking(String bookingId, RaterRole asRole) {
    return _myRatedBookings[bookingId]?.contains(asRole.name) ?? false;
  }

  Future<Rating> submitRating({
    required String bookingId,
    required String chargerId,
    required String raterId,
    required RaterRole raterRole,
    required String rateeId,
    required int stars,
    String? comment,
  }) async {
    assert(stars >= 1 && stars <= 5, 'stars must be between 1 and 5');

    final rating = Rating(
      id: _uuid.v4(),
      bookingId: bookingId,
      chargerId: chargerId,
      raterId: raterId,
      raterRole: raterRole,
      rateeId: rateeId,
      stars: stars,
      comment: (comment == null || comment.trim().isEmpty) ? null : comment.trim(),
    );

    _myRatedBookings.putIfAbsent(bookingId, () => {}).add(raterRole.name);
    // Invalidate any cached summary for the ratee so the next view of
    // their profile/charger reflects this new rating.
    _summaryCache.remove(rateeId);
    notifyListeners();

    await _db.collection('ratings').doc(rating.id).set(rating.toFirestore());
    return rating;
  }

  /// Fetches (and caches for this session) the average rating + count
  /// for any user - pass a hostId to show "Host rating: 4.8 (12)" on a
  /// charger card, or a driverId to show a driver's rating on the host
  /// side.
  Future<RatingSummary> fetchSummaryFor(String userId, {bool forceRefresh = false}) async {
    if (!forceRefresh && _summaryCache.containsKey(userId)) {
      return _summaryCache[userId]!;
    }
    try {
      final snap = await _db.collection('ratings').where('rateeId', isEqualTo: userId).get();
      if (snap.docs.isEmpty) {
        _summaryCache[userId] = RatingSummary.empty;
        return RatingSummary.empty;
      }
      final stars = snap.docs.map((d) => (d.data()['stars'] as num?)?.toInt() ?? 0).toList();
      final avg = stars.reduce((a, b) => a + b) / stars.length;
      final summary = RatingSummary(average: avg, count: stars.length);
      _summaryCache[userId] = summary;
      return summary;
    } catch (e) {
      debugPrint('RatingService.fetchSummaryFor failed: $e');
      return RatingSummary.empty;
    }
  }

  /// Synchronous cached read (returns null if not yet fetched this
  /// session) - handy for widgets that already trigger fetchSummaryFor
  /// in initState and just want the cached value on rebuild.
  RatingSummary? cachedSummaryFor(String userId) => _summaryCache[userId];
}
