import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/rating.dart';
import '../../services/rating_service.dart';
import '../../theme/ps_ev_theme.dart';
import '../../theme/ps_ev_app_bar.dart';

/// FIX (7/9 update, item #12 - "can't find reviews on stations"): shows
/// every individual review (star rating + written comment) left by
/// drivers for a specific charging station. Reached from the station
/// detail panel next to the aggregate rating badge (see
/// screens/driver/driver_home_screen.dart).
class StationReviewsScreen extends StatefulWidget {
  final String chargerId;
  final String chargerLabel;
  const StationReviewsScreen({super.key, required this.chargerId, required this.chargerLabel});

  @override
  State<StationReviewsScreen> createState() => _StationReviewsScreenState();
}

class _StationReviewsScreenState extends State<StationReviewsScreen> {
  late Future<List<Rating>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<RatingService>().fetchReviewsForCharger(widget.chargerId);
  }

  Future<void> _refresh() async {
    final fresh = context.read<RatingService>().fetchReviewsForCharger(widget.chargerId, forceRefresh: true);
    setState(() => _future = fresh);
    await fresh;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PsEvAppBar(title: 'Reviews - ${widget.chargerLabel}'),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Rating>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final reviews = snapshot.data ?? const <Rating>[];
            if (reviews.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(
                      child: Text(
                        'No reviews yet for this station.',
                        style: TextStyle(color: PsEvColors.mutedText),
                      ),
                    ),
                  ),
                ],
              );
            }
            final average = reviews.map((r) => r.stars).reduce((a, b) => a + b) / reviews.length;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: PsEvColors.emeraldPale, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: PsEvColors.amber, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        '${average.toStringAsFixed(1)} - ${reviews.length} review${reviews.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: PsEvColors.emeraldChipText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ...reviews.map((r) => _ReviewCard(rating: r)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Rating rating;
  const _ReviewCard({required this.rating});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: FirebaseFirestore.instance.collection('users').doc(rating.raterId).get(),
                    builder: (context, snapshot) {
                      var name = 'EVPair driver';
                      if (snapshot.hasData && snapshot.data!.exists) {
                        final data = snapshot.data!.data();
                        final first = data?['firstName'] as String? ?? '';
                        final last = data?['lastName'] as String? ?? '';
                        final full = [first, last].where((v) => v.trim().isNotEmpty).join(' ');
                        if (full.isNotEmpty) name = full;
                      }
                      return Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13));
                    },
                  ),
                ),
                Text(dateFmt.format(rating.createdAt), style: const TextStyle(color: PsEvColors.mutedText, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: List.generate(5, (i) {
                return Icon(
                  i < rating.stars ? Icons.star : Icons.star_border,
                  size: 16,
                  color: PsEvColors.amber,
                );
              }),
            ),
            if (rating.comment != null && rating.comment!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(rating.comment!, style: const TextStyle(fontSize: 13, color: PsEvColors.slateText)),
            ],
          ],
        ),
      ),
    );
  }
}
