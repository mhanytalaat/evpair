import 'dart:async';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'services/booking_service.dart';
import 'services/wallet_service.dart';
import 'services/auth_service.dart';
import 'services/partner_service.dart';
import 'services/rating_service.dart';
import 'services/locations_service.dart';
import 'services/power_options_service.dart';
import 'services/car_models_service.dart';
import 'state/app_state.dart';
import 'theme/ps_ev_theme.dart';
import 'screens/root/app_root.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // Everything now runs inside a guarded zone so that ANY uncaught error
  // (Firebase init failure, Firestore hydrate failure, network issue,
  // etc.) shows a friendly EVPair error screen instead of a hard iOS
  // "EVPair Crashed" system dialog with no useful info for the tester.
  //
  // IMPORTANT CAVEAT (see chat): this guard only catches DART-level
  // exceptions. It cannot catch native iOS crashes that happen before
  // Flutter's engine finishes starting - e.g. a GoogleService-Info.plist
  // bundle ID mismatch, or a missing Info.plist permission usage string
  // (NSLocationWhenInUseUsageDescription, NSCameraUsageDescription,
  // NSPhotoLibraryUsageDescription). Those must be fixed at the native
  // project level, not in this file.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('Flutter framework error: ${details.exception}');
      debugPrint(details.stack.toString());
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Platform error: $error');
      debugPrint(stack.toString());
      return true;
    };
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final walletService = WalletService();
      final authService = AuthService();
      await authService.tryAutoSignIn();
      final appState = AppState();
      if (authService.uid != null) {
        appState.currentUserId = authService.uid;
      }
      // Governorates/areas live in Firestore (auto-seeded from the
      // bundled list on first run) - see services/locations_service.dart.
      final locationsService = LocationsService();
      await locationsService.hydrate();
      // kW options in Firestore: same auto-seed-then-read-live pattern -
      // see services/power_options_service.dart.
      final powerOptionsService = PowerOptionsService();
      await powerOptionsService.hydrate();
      // Car brand/model options in Firestore: same pattern again - see
      // services/car_models_service.dart.
      final carModelsService = CarModelsService();
      await carModelsService.hydrate();
      await appState.hydrateFromFirestore();
      if (authService.uid != null) {
        await walletService.hydrateFromFirestore(authService.uid!);
      }
      final partnerService = PartnerService(walletService: walletService);
      if (authService.uid != null) {
        await partnerService.hydrate(authService.uid!);
      }
      final ratingService = RatingService();
      if (authService.uid != null) {
        await ratingService.hydrate(authService.uid!);
      }
      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: appState),
            ChangeNotifierProvider<WalletService>.value(value: walletService),
            ChangeNotifierProvider(
              create: (_) => BookingService(walletService: walletService),
            ),
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<PartnerService>.value(value: partnerService),
            ChangeNotifierProvider<RatingService>.value(value: ratingService),
            ChangeNotifierProvider<LocationsService>.value(value: locationsService),
            ChangeNotifierProvider<PowerOptionsService>.value(value: powerOptionsService),
            ChangeNotifierProvider<CarModelsService>.value(value: carModelsService),
          ],
          child: const EvPairApp(),
        ),
      );
    } catch (error, stack) {
      debugPrint('EVPair startup failed: $error');
      debugPrint(stack.toString());
      runApp(StartupFailureApp(error: error.toString()));
    }
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error');
    debugPrint(stack.toString());
  });
}

class EvPairApp extends StatelessWidget {
  const EvPairApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EVPair',
      debugShowCheckedModeBanner: false,
      theme: buildPsEvTheme(),
      home: const AppRoot(),
    );
  }
}

/// Shown instead of a hard crash whenever Firebase init, auto sign-in,
/// or the initial Firestore hydrate throws. Gives the tester a "Retry"
/// action and a visible error string instead of iOS's generic
/// "EVPair Crashed" dialog with no diagnostic value.
///
/// NOTE: this only ever runs if the crash happens in DART code. If the
/// app crashes before this file even executes (see the caveat above),
/// this screen never has a chance to appear - that's a strong signal
/// the crash is native, not caught here.
class StartupFailureApp extends StatelessWidget {
  final String error;
  const StartupFailureApp({super.key, required this.error});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 72),
                const SizedBox(height: 20),
                const Text(
                  'EVPair could not start',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'This is usually a network, Firebase, or account sync '
                  'issue. Please check your internet connection and try '
                  'again. If this keeps happening, share this message with '
                  'support.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    error,
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => main(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text('Retry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
