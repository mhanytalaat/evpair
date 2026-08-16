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

    runApp(
        MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => AppState(),),
                ChangeNotifierProvider<WalletService>.value(value: walletService,),
                ChangeNotifierProvider(create: (_) => BookingService(walletService:walletService,
                ),
                ),
                
                Provider(
                  create: (_) => AuthService()
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
