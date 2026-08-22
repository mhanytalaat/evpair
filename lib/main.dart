import 'dart:async';
import 'dart:ui';

import 'package:provider/provider.dart';
import 'services/booking_service.dart';
import 'services/wallet_service.dart';
import 'services/auth_service.dart';
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
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Catches Flutter framework/widget-build errors (red screen errors).
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('Flutter framework error: ${details.exception}');
      debugPrint(details.stack.toString());
    };

    // Catches errors outside the Flutter framework (platform channels,
    // async errors not caught elsewhere, etc.).
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

      // Firebase Auth persists sessions natively (no manual storage
      // needed). Restore any existing session and load this user's cars
      // + the charger marketplace before the first frame is drawn, so a
      // returning user lands straight in the app with their data already
      // in place.
      final authService = AuthService();
      await authService.tryAutoSignIn();

      final appState = AppState();
      if (authService.uid != null) {
        appState.currentUserId = authService.uid;
      }
      await appState.hydrateFromFirestore();

      // Load the signed-in user's wallet balance/transactions from
      // Firestore as well. Without this, WalletService starts from an
      // empty in-memory state every cold launch, which is why the
      // balance appears to "disappear" after signing out and back in -
      // it was never being read back from Firestore in the first place.
      if (authService.uid != null) {
        await walletService.hydrateFromFirestore(authService.uid!);
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
