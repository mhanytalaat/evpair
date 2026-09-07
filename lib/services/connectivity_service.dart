import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Tracks whether this device currently has a working internet
/// connection, so the rest of the app can react (item #1 of the 7/9
/// update - "white screen when there's no internet").
///
/// This deliberately does NOT depend on the `connectivity_plus` package
/// (which may or may not already be in pubspec.yaml) - it instead does a
/// real, lightweight DNS lookup against Google's public DNS/host, which
/// is a much more reliable signal than "is Wi-Fi/mobile data connected"
/// (a phone can be connected to a Wi-Fi network with no actual internet
/// access, which connectivity_plus alone would incorrectly report as
/// "online").
///
/// On Flutter Web, `dart:io`'s `InternetAddress.lookup` is not
/// available, so this always reports "online" on web and simply relies
/// on Firestore's own network handling there.
///
/// Usage:
///   - Call `ConnectivityService.instance.start()` once during app
///     bootstrap (see screens/system/app_bootstrap.dart).
///   - Wrap any screen that should show an offline state with
///     `OfflineGate` (see screens/system/offline_screen.dart), or listen
///     to `isOnline`/`addListener` directly.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService._internal();
  static final ConnectivityService instance = ConnectivityService._internal();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Timer? _timer;
  bool _checking = false;

  /// Starts a periodic background check (every 5 seconds). Safe to call
  /// more than once - subsequent calls are ignored while already running.
  void start({Duration interval = const Duration(seconds: 5)}) {
    if (_timer != null) return;
    // Run one check immediately so the very first frame already has an
    // accurate reading instead of defaulting to "online" for 5 seconds.
    unawaited(checkNow());
    _timer = Timer.periodic(interval, (_) => checkNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Performs a single connectivity check right now. Safe to call
  /// directly from a "Retry" button - callers don't need to wait for the
  /// next periodic tick.
  Future<bool> checkNow() async {
    if (_checking) return _isOnline;
    _checking = true;
    bool result;
    if (kIsWeb) {
      // dart:io isn't available on web; assume online and let Firestore's
      // own web SDK handle offline/online transitions internally.
      result = true;
    } else {
      try {
        final lookup = await InternetAddress.lookup('firebase.google.com')
            .timeout(const Duration(seconds: 4));
        result = lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
      } on SocketException catch (_) {
        result = false;
      } on TimeoutException catch (_) {
        result = false;
      } catch (_) {
        result = false;
      }
    }
    _checking = false;
    if (result != _isOnline) {
      _isOnline = result;
      notifyListeners();
    }
    return _isOnline;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
