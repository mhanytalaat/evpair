import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/rating.dart';
import '../../services/rating_service.dart';
import '../../theme/ps_ev_theme.dart';

/// Reusable star-rating dialog used for BOTH directions:
///   - a driver rating the host after a completed booking
///   - a host rating the driver after a completed booking
///
/// Call `showRateUserDialog(...)` rather than constructing this widget
/// directly - it handles submission + a confirmation snackbar for you.
class RateUserDialog extends StatefulWidget {
  final String title;
  final String subtitle;

  const RateUserDialog({super.key, required this.title, required this.subtitle});

  @override
  State<RateUserDialog> createState() => _RateUserDialogState();
}

class _RateUserDialogState extends State<RateUserDialog> {
  int _stars = 5;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: PsEvColors.mutedText)),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  final starValue = index + 1;
                  final filled = starValue <= _stars;
                  return IconButton(
                    onPressed: () => setState(() => _stars = starValue),
                    icon: Icon(
                      filled ? Icons.star : Icons.star_border,
                      color: PsEvColors.amber,
                      size: 32,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                _starLabel(_stars),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PsEvColors.mutedText),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                hintText: 'Share more about your experience...',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Skip'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, (_stars, _commentCtrl.text)),
          child: const Text('Submit Rating'),
        ),
      ],
    );
  }

  String _starLabel(int stars) {
    switch (stars) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      default:
        return 'Excellent';
    }
  }
}

/// Shows the rating dialog and, if the user submits (doesn't tap
/// "Skip"), saves it through RatingService and shows a confirmation
/// snackbar. Returns true if a rating was submitted, false if skipped.
Future<bool> showRateUserDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String bookingId,
  required String chargerId,
  required String raterId,
  required RaterRole raterRole,
  required String rateeId,
}) async {
  final result = await showDialog<(int, String)>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RateUserDialog(title: title, subtitle: subtitle),
  );

  if (result == null || !context.mounted) return false;

  final (stars, comment) = result;
  await context.read<RatingService>().submitRating(
        bookingId: bookingId,
        chargerId: chargerId,
        raterId: raterId,
        raterRole: raterRole,
        rateeId: rateeId,
        stars: stars,
        comment: comment,
      );

  if (!context.mounted) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Thanks for your rating!')),
  );
  return true;
}
