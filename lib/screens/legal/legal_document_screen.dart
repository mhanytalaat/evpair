import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/ps_ev_theme.dart';

/// Displays a single legal document (Terms & Conditions or Privacy
/// Policy) whose content lives in Firestore at:
///
///   legal/{documentId}
///     - title: String
///     - body: String   (plain text / simple line breaks; swap for
///                        flutter_markdown's Text.markdown(body) if you
///                        want bold/headers/links rendered from Firestore)
///     - version: String
///     - updatedAt: Timestamp
///
/// Editing the document (from an admin screen, or directly in the
/// Firestore console) instantly updates what every driver/host sees
/// here - no app release needed for wording changes. The exact same
/// `legal/{documentId}` documents can be read by your website (with an
/// open/public read security rule on the `legal` collection) so the
/// app and the website always show the same current version.
class LegalDocumentScreen extends StatelessWidget {
  final String documentId; // 'termsAndConditions' or 'privacyPolicy'
  final String title;

  const LegalDocumentScreen({super.key, required this.documentId, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: PsEvColors.slate950,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('legal').doc(documentId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load this document. Please check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PsEvColors.mutedText),
                ),
              ),
            );
          }
          final data = snapshot.data?.data();
          if (data == null || (data['body'] as String?)?.trim().isEmpty != false) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This document has not been published yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PsEvColors.mutedText),
                ),
              ),
            );
          }

          final body = data['body'] as String;
          final version = data['version'] as String?;
          final updatedAt = data['updatedAt'];
          final updatedLabel = updatedAt is Timestamp
              ? DateFormat('MMM d, yyyy').format(updatedAt.toDate())
              : null;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (version != null || updatedLabel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (version != null) PsEvTag(label: 'v$version'),
                      if (updatedLabel != null) PsEvTag(label: 'Updated $updatedLabel'),
                    ],
                  ),
                ),
              Text(body, style: const TextStyle(fontSize: 14, height: 1.5, color: PsEvColors.slate950)),
            ],
          );
        },
      ),
    );
  }
}
