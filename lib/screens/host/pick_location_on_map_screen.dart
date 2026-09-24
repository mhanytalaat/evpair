import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/ps_ev_theme.dart';

/// Interactive map picker used by ChargerFormScreen: the host pans/zooms
/// to their charger's real location and taps to drop a pin exactly there.
/// Returns the picked (lat, lng) as a record to the caller, which stores
/// it directly - no link parsing, no manual coordinate typing required.
/// This is more reliable than a pasted Google Maps link, since many
/// shortened links (maps.app.goo.gl/...) don't contain usable
/// coordinates at all.
///
/// FIX (9/24 update - "having get me exact location... having this get
/// my location icon"): added a "use my current location" floating
/// button. Previously the only way to place the pin was manually
/// panning/zooming/tapping the map - now a host who is standing at (or
/// near) the actual charger location can tap this button once to jump
/// straight to their own GPS position and drop the pin there, then
/// still fine-tune with a tap if needed. Uses the exact same
/// Geolocator permission flow already proven working elsewhere in the
/// app (see screens/driver/driver_home_screen.dart's
/// _recenterToMyLocation) - no new Apple/Google Play permissions are
/// needed since Location When In Use is already requested by the app.
class PickLocationOnMapScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  const PickLocationOnMapScreen({super.key, required this.initialLat, required this.initialLng});

  @override
  State<PickLocationOnMapScreen> createState() => _PickLocationOnMapScreenState();
}

class _PickLocationOnMapScreenState extends State<PickLocationOnMapScreen> {
  late LatLng _picked;
  final MapController _mapController = MapController();
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _picked = LatLng(widget.initialLat, widget.initialLng);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Please enable Location Services to use your current location.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showMessage('Location permission denied.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage('Location permission is disabled. Enable it in Settings to use this feature.');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      setState(() => _picked = point);
      _mapController.move(point, 17);
    } catch (e) {
      _showMessage('Could not get your current location right now.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Exact Charger Location'),
        backgroundColor: Colors.white,
        foregroundColor: PsEvColors.slate950,
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _picked,
              initialZoom: 16,
              onTap: (tapPosition, point) => setState(() => _picked = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.evpairapp.evpair',
                maxNativeZoom: 19,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _picked,
                    width: 46,
                    height: 46,
                    child: const Icon(Icons.location_on, size: 46, color: PsEvColors.emerald),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              elevation: 4,
              shadowColor: Colors.black26,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Pan and zoom the map, then tap exactly where your charger is - or tap the location '
                  'icon below to jump to where you are right now.',
                  style: TextStyle(fontSize: 12, color: PsEvColors.mutedText),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          // NEW: "use my current location" button.
          Positioned(
            right: 16,
            bottom: 100,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 4,
              shadowColor: Colors.black26,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _locating ? null : _useMyLocation,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _locating
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, color: PsEvColors.emerald, size: 22),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: PsEvFilledButton(
              icon: Icons.check_circle_outline,
              label: 'Use This Location',
              onTap: () => Navigator.pop(context, (lat: _picked.latitude, lng: _picked.longitude)),
            ),
          ),
        ],
      ),
    );
  }
}
