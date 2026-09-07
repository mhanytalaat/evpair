import 'package:flutter/material.dart';
import '../../theme/ps_ev_theme.dart';

/// Animated logo splash shown while the app boots (item #2 of the 7/9
/// update - "logo animated at the beginning before loading").
///
/// Purely a visual widget: it fades + scales the EVPair bolt logo in on
/// a loop-free, one-shot animation, and shows a small progress line
/// underneath together with [statusText] so the user gets feedback
/// during the real Firebase/Firestore bootstrap happening behind it
/// (see screens/system/app_bootstrap.dart, which is the only place that
/// should construct this widget).
class SplashScreen extends StatefulWidget {
  final String statusText;
  const SplashScreen({super.key, this.statusText = 'Loading EVPair...'});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _scale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fade.value,
                  child: Transform.scale(scale: _scale.value, child: child),
                );
              },
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF0D9488)]),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [BoxShadow(color: PsEvColors.emerald.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10))],
                ),
                child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 52),
              ),
            ),
            const SizedBox(height: 22),
            FadeTransition(
              opacity: _fade,
              child: const Text(
                'EVPair',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: PsEvColors.slate950),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: PsEvColors.slate200,
                valueColor: const AlwaysStoppedAnimation(PsEvColors.emerald),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.statusText,
              style: const TextStyle(color: PsEvColors.mutedText, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
