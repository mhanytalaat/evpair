class AvailabilitySlot {
  final String id;
  final String chargerId;
  final DateTime start;
  final DateTime end;
  bool isBooked;

  /// Optional label shown next to a slot generated as part of a weekly
  /// recurring batch (e.g. "Every Sun"), so the host can tell it apart
  /// from a one-off addition.
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

  bool canFit(DateTime reqStart, DateTime reqEnd) {
    return !isBooked &&
        !reqStart.isBefore(start) &&
        !reqEnd.isAfter(end) &&
        reqStart.isBefore(reqEnd);
  }
}
