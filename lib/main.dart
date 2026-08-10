import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/booking_service.dart';
import 'services/wallet_service.dart';
import 'services/auth_service.dart';
import 'state/app_state.dart';
import 'theme/ps_ev_theme.dart';
import 'screens/root/app_root.dart';

void main() {
  final walletService = WalletService();

  // Seed a generous demo balance directly (bypassing the top-up approval
  // flow, which is only meant for real driver-submitted top-ups). Raised
  // from the previous 500 EGP: with multi-hour demo slots at 22 kW, a
  // single booking's held estimate can easily exceed 500 EGP, which made
  // it look like a "bug" (insufficient balance) when it was really just a
  // too-small starting balance for the demo's longer slots.
  walletService.seedBalance(kCurrentUserId, 3000);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => walletService),
        ChangeNotifierProvider(create: (_) => BookingService(walletService: walletService)),
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => AuthService()),
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
