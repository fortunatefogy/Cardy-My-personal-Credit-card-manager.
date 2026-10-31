import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

/// Shared page motion used when opening a major Cardy screen.
PageRoute<T> cardyPageRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.horizontal,
        fillColor: Theme.of(context).scaffoldBackgroundColor,
        child: child,
      ),
    );
