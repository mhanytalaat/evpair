import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/rating.dart';
import '../services/rating_service.dart';
import '../theme/ps_ev_theme.dart';

/// Shows a small "★ 4.8 (12)" badge for a given user (typically a
/// charger's hostId), pulled from RatingService.fetchSummaryFor. Used in
/// the driver's station detail panel so ratings submitted after a
/// completed booking (see rate_user_dialog.dart) actually surface
/// somewhere for OTHER drivers browsing that station - previously a
/// rating was saved to Firestore but never displayed anywhere in the
/// driver-facing station UI at all.
///
/// Fetches once per widget lifetime (RatingService caches the result
/// internally too, so re-showing the same station is instant on repeat
/// views). Shows nothing (an empty SizedBox) while loading or if there
/// are zero ratings yet, so it never clutters the UI with a "No ratings
/// yet" message on every single station card.
class HostRatingBadge extends StatefulWidget {
  final String hostId;
  const HostRatingBadge({super.key, required this.hostId});

  @override
  State<HostRatingBadge> createState() => _HostRatingBadgeState();
}

class _HostRatingBadgeState extends State<HostRatingBadge> {
  RatingSummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HostRatingBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hostId != widget.hostId) _load();
  }

  Future<void> _load() async {
    final ratingService = context.read<RatingService>();
    final cached = ratingService.cachedSummaryFor(widget.hostId);
    if (cached != null && mounted) setState(() => _summary = cached);
    final fresh = await ratingService.fetchSummaryFor(widget.hostId);
    if (mounted) setState(() => _summary = fresh);
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null || summary.count == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 6, top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: PsEvColors.amberChip, borderRadius: BorderRadius.circular(PsEvRadii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 12, color: PsEvColors.amberChipText),
          const SizedBox(width: 3),
          Text(
            '${summary.average.toStringAsFixed(1)} (${summary.count})',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PsEvColors.amberChipText),
          ),
        ],
      ),
    );
  }
}
