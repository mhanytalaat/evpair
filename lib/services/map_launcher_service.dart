import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Presents a provider-neutral chooser before opening an external maps app.
Future<void> showMapAppChooser(
  BuildContext context, {
  required double latitude,
  required double longitude,
  String? label,
}) async {
  final destination = label?.trim().isNotEmpty == true ? label!.trim() : 'Charger location';

  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('Apple Maps'),
            subtitle: Text(destination),
            onTap: () => Navigator.pop(sheetContext, 'apple'),
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Google Maps'),
            subtitle: Text(destination),
            onTap: () => Navigator.pop(sheetContext, 'google'),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Cancel'),
            onTap: () => Navigator.pop(sheetContext),
          ),
        ],
      ),
    ),
  );

  if (choice == null || !context.mounted) return;

  final Uri uri = choice == 'apple'
      ? Uri.https('maps.apple.com', '/', {
          'll': '$latitude,$longitude',
          'q': destination,
        })
      : Uri.https('www.google.com', '/maps/search/', {
          'api': '1',
          'query': '$latitude,$longitude',
        });

  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the selected maps app.')),
    );
  }
}
