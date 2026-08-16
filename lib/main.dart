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
import 'package:flutter/widgets.dart';


Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
    );

  final walletService = WalletService ();

  // Firebase Auth persists sessions natively (no manual storage needed).
  // Restore any existing session and load this user's cars + the charger
  // marketplace before the first frame is drawn, so a returning user
  // lands straight in the app with their data already in place.
  final authService = AuthService();
  await authService.tryAutoSignIn();

  final appState = AppState();
  if (authService.uid != null) {
    appState.currentUserId = authService.uid;
  }
  await appState.hydrateFromFirestore();

    runApp(
        MultiProvider(
            providers: [
              ChangeNotifierProvider<AppState>.value(value: appState,),
                ChangeNotifierProvider<WalletService>.value(value: walletService,),
                ChangeNotifierProvider(create: (_) => BookingService(walletService:walletService,
                ),
                ),
                
                ChangeNotifierProvider<AuthService>.value(
                  value: authService,
                  ),


            ],
            
            child: const EvPairApp(),

        ),
  
    );
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
