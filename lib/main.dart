import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'screens/system/app_bootstrap.dart';

/// FIX (7/9 update, items #1 and #2): all the Firebase/Firestore
/// bootstrap work that used to run here, synchronously, BEFORE the
/// first `runApp` call, has moved into [AppBootstrap] (see
/// screens/system/app_bootstrap.dart). That widget is now what actually
/// owns the splash screen, the up-front + ongoing connectivity checks,
/// and the "could not start" retry screen - `main()` itself just wires
/// up global error handlers and calls `runApp` immediately, so the very
/// first frame the user ever sees is the branded splash, never a blank
/// white screen.
Future<void> main() async {
  runZonedGuarded(() {
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
    runApp(const AppBootstrap());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error');
    debugPrint(stack.toString());
  });
}
