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
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';
import 'state/app_state.dart';
import 'theme/ps_ev_theme.dart';
import 'screens/root/app_root.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
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
      // Notifications (in-app, Firestore-backed) must exist before
      // WalletService/BookingService, since both now create
      // notifications as part of their normal mutations (top-up
      // review, booking request/approve/decline).
      final notificationService = NotificationService();
      final walletService = WalletService(notificationService: notificationService);
      final authService = AuthService();
      await authService.tryAutoSignIn();
      final appState = AppState();
      if (authService.uid != null) {
        appState.currentUserId = authService.uid;
      }
      final locationsService = LocationsService();
      await locationsService.hydrate();
      final powerOptionsService = PowerOptionsService();
      await powerOptionsService.hydrate();
      final carModelsService = CarModelsService();
      await carModelsService.hydrate();
      await appState.hydrateFromFirestore();
      final bookingService = BookingService(walletService: walletService, notificationService: notificationService);
      if (authService.uid != null) {
        await walletService.hydrateFromFirestore(authService.uid!);
        // Live listeners for this user's bookings (as driver AND host)
        // and notifications - see booking_service.dart/notification_service.dart.
        // Also register this device for push notifications (see
        // push_notification_service.dart) - without this call, a
        // notification document would still be created correctly, but
        // there would be no device token to actually push to.
        bookingService.hydrate(authService.uid!);
        notificationService.listenFor(authService.uid!);
        await PushNotificationService.initAndRegister(authService.uid!);
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
            ChangeNotifierProvider<BookingService>.value(value: bookingService),
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<PartnerService>.value(value: partnerService),
            ChangeNotifierProvider<RatingService>.value(value: ratingService),
            ChangeNotifierProvider<LocationsService>.value(value: locationsService),
            ChangeNotifierProvider<PowerOptionsService>.value(value: powerOptionsService),
            ChangeNotifierProvider<CarModelsService>.value(value: carModelsService),
            ChangeNotifierProvider<NotificationService>.value(value: notificationService),
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
