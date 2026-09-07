import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import '../../services/booking_service.dart';
import '../../services/wallet_service.dart';
import '../../services/auth_service.dart';
import '../../services/partner_service.dart';
import '../../services/rating_service.dart';
import '../../services/locations_service.dart';
import '../../services/power_options_service.dart';
import '../../services/car_models_service.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/connectivity_service.dart';
import '../../state/app_state.dart';
import '../root/app_root.dart';
import 'splash_screen.dart';
import 'offline_screen.dart';
import '../../theme/ps_ev_theme.dart';

/// EVPair's app-wide theme, applied consistently across every boot phase.
final ThemeData _appTheme = buildPsEvTheme();

/// Owns the entire app startup sequence (splash -> offline check ->
/// Firebase init -> hydrate services -> ready).
///
/// ============================================================
/// HISTORY OF TWO BUGS FOUND IN EARLIER VERSIONS OF THIS FILE -
/// READ BEFORE CHANGING THE ORDERING BELOW AGAIN:
/// ============================================================
///
/// BUG 1 (`ProviderNotFoundException: ...AuthService... above this
/// SignInScreen widget`): an earlier version built `MultiProvider`
/// INSIDE `MaterialApp`'s `home:` property instead of wrapping the
/// whole `MaterialApp`/`Navigator`. Any route later pushed via
/// `Navigator.push` (e.g. SignInScreen) became a SIBLING route outside
/// that provider scope, so it could never find AuthService/AppState/etc.
/// FIX: `MultiProvider` must wrap the entire `MaterialApp` (see build()
/// below), not just its `home` content.
///
/// BUG 2 (`[core/no-app] No Firebase App '[DEFAULT]' has been created -
/// call Firebase.initializeApp()`, i.e. "Firebase has not been correctly
/// initialized"): the FIX for Bug 1 above over-corrected by constructing
/// every service (AuthService(), WalletService(), etc.) synchronously in
/// `initState()`, BEFORE `_boot()`'s `await Firebase.initializeApp(...)`
/// had actually completed. Several of these services touch
/// `FirebaseAuth.instance`/`FirebaseFirestore.instance` directly in
/// their constructor, which throws immediately if no Firebase app has
/// been created yet - which is exactly what "Firebase has not been
/// correctly initialized" means, and exactly what happened here.
///
/// THE CORRECT FIX (this version): services are now constructed ONLY
/// AFTER `await Firebase.initializeApp(...)` has successfully completed,
/// inside `_boot()`. Until that happens, the splash/offline/failure
/// screens are shown via a PLAIN `MaterialApp` with NO providers at all
/// (those screens never call `context.read<...>()`, so they don't need
/// any). Only once Firebase is ready AND every service exists does
/// `build()` switch to returning `MultiProvider(... child: MaterialApp(
/// ... home: AppRoot() ...))` - and because that MultiProvider wraps the
/// WHOLE MaterialApp/Navigator (not just `home`'s content), every route
/// pushed afterwards (SignInScreen, RegisterScreen, etc.) is guaranteed
/// to be inside its scope, which is also what fixes Bug 1 for good.
///
/// In short: Bug 1's fix was "providers must wrap the whole MaterialApp"
/// and Bug 2's fix is "but only construct those providers' services
/// AFTER Firebase is ready" - both are true at the same time in the
/// structure below.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

enum _BootPhase { loading, offline, failed, ready }

class _AppBootstrapState extends State<AppBootstrap> {
  _BootPhase _phase = _BootPhase.loading;
  String _statusText = 'Starting up...';
  String? _errorText;

  // These are all created ONLY after Firebase.initializeApp() succeeds
  // (see _boot() below) - never touched before that, and never rebuilt
  // afterwards for the lifetime of the app.
  NotificationService? _notificationService;
  WalletService? _walletService;
  AuthService? _authService;
  AppState? _appState;
  LocationsService? _locationsService;
  PowerOptionsService? _powerOptionsService;
  CarModelsService? _carModelsService;
  BookingService? _bookingService;
  PartnerService? _partnerService;
  RatingService? _ratingService;

  @override
  void initState() {
    super.initState();
    // Safe pre-Firebase: does its own plain DNS lookup, touches no
    // Firebase API at all.
    ConnectivityService.instance.start();
    _boot();
  }

  Future<T> _withTimeout<T>(Future<T> future, {String label = 'Loading'}) {
    return future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw TimeoutException('$label timed out - please check your connection.'),
    );
  }

  Future<void> _boot() async {
    setState(() {
      _phase = _BootPhase.loading;
      _statusText = 'Checking connection...';
    });

    final online = await ConnectivityService.instance.checkNow();
    if (!online) {
      setState(() => _phase = _BootPhase.offline);
      return;
    }

    try {
      setState(() => _statusText = 'Connecting...');
      // MUST complete before ANY service below is constructed - several
      // of them touch FirebaseAuth.instance / FirebaseFirestore.instance
      // directly in their constructor.
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      // --- Safe to construct every Firebase-backed service now. ---
      _notificationService = NotificationService();
      _walletService = WalletService(notificationService: _notificationService!);
      _authService = AuthService();
      _appState = AppState();
      _locationsService = LocationsService();
      _powerOptionsService = PowerOptionsService();
      _carModelsService = CarModelsService();
      _bookingService = BookingService(walletService: _walletService!, notificationService: _notificationService!);
      _partnerService = PartnerService(walletService: _walletService!);
      _ratingService = RatingService();

      setState(() => _statusText = 'Signing you in...');
      await _withTimeout(_authService!.tryAutoSignIn(), label: 'Sign-in');
      if (_authService!.uid != null) {
        _appState!.currentUserId = _authService!.uid;
      }

      setState(() => _statusText = 'Loading app data...');
      await _withTimeout(_locationsService!.hydrate(), label: 'Locations');
      await _withTimeout(_powerOptionsService!.hydrate(), label: 'Power options');
      await _withTimeout(_carModelsService!.hydrate(), label: 'Car models');
      await _withTimeout(_appState!.hydrateFromFirestore(), label: 'Stations');

      if (_authService!.uid != null) {
        setState(() => _statusText = 'Loading your account...');
        await _withTimeout(_walletService!.hydrateFromFirestore(_authService!.uid!), label: 'Wallet');
        if (_authService!.isAdmin) {
          _walletService!.listenToAllTopUpRequestsForAdmin();
        }
        _bookingService!.hydrate(_authService!.uid!);
        _notificationService!.listenFor(_authService!.uid!);
        await PushNotificationService.initAndRegister(_authService!.uid!);
        await _partnerService!.hydrate(_authService!.uid!);
        await _ratingService!.hydrate(_authService!.uid!);
      }

      if (!mounted) return;
      setState(() => _phase = _BootPhase.ready);
    } on TimeoutException catch (e) {
      final stillOnline = await ConnectivityService.instance.checkNow();
      if (!mounted) return;
      setState(() {
        if (!stillOnline) {
          _phase = _BootPhase.offline;
        } else {
          _phase = _BootPhase.failed;
          _errorText = e.message ?? 'The app took too long to start.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _BootPhase.failed;
        _errorText = e.toString();
      });
    }
  }

  Widget _nonReadyHome() {
    switch (_phase) {
      case _BootPhase.offline:
        return const OfflineScreen();
      case _BootPhase.failed:
        return _BootFailureScreen(error: _errorText ?? 'Unknown error', onRetry: _boot);
      case _BootPhase.loading:
      case _BootPhase.ready: // unreachable here, kept for switch exhaustiveness
        return SplashScreen(statusText: _statusText);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _BootPhase.ready) {
      // Only reachable once Firebase is initialized AND every service
      // above has been constructed - so it's always safe to use them
      // here. MultiProvider wraps the WHOLE MaterialApp/Navigator, so
      // every route ever pushed from here on (SignInScreen,
      // RegisterScreen, etc.) is guaranteed to be inside its scope.
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: _appState!),
          ChangeNotifierProvider<WalletService>.value(value: _walletService!),
          ChangeNotifierProvider<BookingService>.value(value: _bookingService!),
          ChangeNotifierProvider<AuthService>.value(value: _authService!),
          ChangeNotifierProvider<PartnerService>.value(value: _partnerService!),
          ChangeNotifierProvider<RatingService>.value(value: _ratingService!),
          ChangeNotifierProvider<LocationsService>.value(value: _locationsService!),
          ChangeNotifierProvider<PowerOptionsService>.value(value: _powerOptionsService!),
          ChangeNotifierProvider<CarModelsService>.value(value: _carModelsService!),
          ChangeNotifierProvider<NotificationService>.value(value: _notificationService!),
        ],
        child: MaterialApp(
          title: 'EVPair',
          debugShowCheckedModeBanner: false,
          theme: _appTheme,
          home: const OfflineGate(child: AppRoot()),
        ),
      );
    }
    // Loading / offline / failed: plain MaterialApp, NO providers -
    // these screens never read a provider, and none of the
    // Firebase-backed services exist yet at this point anyway.
    return MaterialApp(
      title: 'EVPair',
      debugShowCheckedModeBanner: false,
      theme: _appTheme,
      home: _nonReadyHome(),
    );
  }
}

class _BootFailureScreen extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;
  const _BootFailureScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                'This is usually a network, Firebase, or account sync issue. Please check your '
                'internet connection and try again. If this keeps happening, share this message '
                'with support.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
                child: Text(error, style: const TextStyle(fontSize: 11, color: Colors.black87)),
              ),
              const SizedBox(height: 24),
              PsEvFilledButton(label: 'Retry', expand: false, onTap: () => onRetry()),
            ],
          ),
        ),
      ),
    );
  }
}
