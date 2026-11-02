import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../theme/cardy_palette.dart';

class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _finished = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _wordmarkOpacity(double t) {
    final fadeIn = ((t - .35) / .15).clamp(0.0, 1.0);
    final fadeOut = 1 - ((t - .85) / .15).clamp(0.0, 1.0);
    return fadeIn * fadeOut;
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;
    return Material(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset(
              'assets/splash/splash.json',
              controller: _controller,
              width: 260,
              height: 260,
              onLoaded: (composition) {
                _controller
                  ..duration = composition.duration
                  ..forward().whenComplete(() {
                    if (mounted) setState(() => _finished = true);
                  });
              },
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => Opacity(
                opacity: _wordmarkOpacity(_controller.value),
                child: child,
              ),
              child: const Text(
                'Cardy',
                style: TextStyle(
                  fontFamily: cardyDisplayFont,
                  fontStyle: FontStyle.italic,
                  fontSize: 46,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: Color(0xFF171719),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
