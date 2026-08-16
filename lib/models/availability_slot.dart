/// Represents a host-defined FREE WINDOW (e.g. "10:00 AM - 10:00 PM").
/// This is the OUTER boundary within which drivers may pick a CUSTOM
/// sub-range (e.g. 2:00 PM - 4:00 PM) - see BookingRequestScreen and
/// BookingService.isRangeAvailable/createRequest. Because multiple
/// drivers can book different, non-overlapping sub-ranges within the SAME
/// window, `isBooked` is kept only for backward compatibility and is not
/// relied upon by the booking flow.
class AvailabilitySlot {
  final String id;
  final String chargerId;
  final DateTime start;
  final DateTime end;
  bool isBooked;

  /// Optional label shown next to a slot generated as part of a weekly
  /// recurring batch (e.g. "Every Sun").
  final String? recurrenceLabel;

  AvailabilitySlot({
    required this.id,
    required this.chargerId,
    required this.start,
    required this.end,
    this.isBooked = false,
    this.recurrenceLabel,
  });

  Duration get duration => end.difference(start);
  int get durationMinutes => duration.inMinutes;

  /// Whether the requested [reqStart]-[reqEnd] range fits entirely within
  /// this window. Does NOT check for overlaps with other drivers' bookings
  /// within the window - that overlap check is done separately by
  /// `BookingService.isRangeAvailable()`.
  bool canFit(DateTime reqStart, DateTime reqEnd) {
    return !reqStart.isBefore(start) && !reqEnd.isAfter(end) && reqStart.isBefore(reqEnd);
  }
}
