import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'credit_card.dart';

class CardWalletStack extends StatefulWidget {
  const CardWalletStack({
    super.key,
    required this.cards,
    required this.cardBuilder,
  });

  final List<CreditCard> cards;
  final Widget Function(CreditCard card, double width, bool front) cardBuilder;

  @override
  State<CardWalletStack> createState() => _CardWalletStackState();
}

class _CardWalletStackState extends State<CardWalletStack>
    with SingleTickerProviderStateMixin {
  static const _peek = 46.0;
  static const _visibleDistance = 3.5;

  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  )..addListener(() {
      setState(() {
        _position =
            lerpDouble(_from, _to, Curves.easeOutCubic.transform(_snap.value))!;
      });
    });
  double _position = 0;
  double _from = 0;
  double _to = 0;

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  void _animateTo(int index) {
    _from = _position;
    _to = index.toDouble();
    _snap.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final lastIndex = widget.cards.length - 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth * .86).clamp(260.0, 360.0);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (_) => _snap.stop(),
          onVerticalDragUpdate: (details) => setState(() {
            _position = (_position - details.delta.dy / _peek)
                .clamp(-.35, lastIndex + .35);
          }),
          onVerticalDragEnd: (details) => _animateTo(
            (_position - (details.primaryVelocity ?? 0) / (_peek * 10))
                .round()
                .clamp(0, lastIndex),
          ),
          child: SizedBox(
            height: width * .63 + _peek * 4,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                for (final index in _drawOrder(lastIndex))
                  _layer(index, index - _position, width),
              ],
            ),
          ),
        );
      },
    );
  }

  List<int> _drawOrder(int lastIndex) {
    final indexes = [
      for (var i = 0; i <= lastIndex; i++)
        if ((i - _position).abs() <= _visibleDistance) i,
    ];
    indexes
        .sort((a, b) => (b - _position).abs().compareTo((a - _position).abs()));
    return indexes;
  }

  Widget _layer(int index, double offset, double width) {
    final distance = offset.abs();
    final front = distance < .5;
    final tile = widget.cardBuilder(widget.cards[index], width, front);
    return Transform.translate(
      offset: Offset(0, offset * _peek),
      child: Transform.scale(
        scale: 1 - distance * .06,
        child: Opacity(
          opacity: 1 - (distance - 2).clamp(0.0, 1.0) * .6,
          child: front
              ? tile
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _animateTo(index),
                  child: IgnorePointer(child: tile),
                ),
        ),
      ),
    );
  }
}
