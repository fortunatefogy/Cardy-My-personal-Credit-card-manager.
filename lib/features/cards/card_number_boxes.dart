import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/services.dart';

class CardNumberBoxes extends StatefulWidget {
  const CardNumberBoxes({
    super.key,
    required this.value,
    required this.maxLength,
    required this.obscure,
    required this.onChanged,
    required this.onToggleVisibility,
  });

  final String value;
  final int maxLength;
  final bool obscure;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggleVisibility;

  @override
  State<CardNumberBoxes> createState() => CardNumberBoxesState();
}

class CardNumberBoxesState extends State<CardNumberBoxes> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(4, (i) => TextEditingController());
    _focusNodes = List.generate(4, (_) => FocusNode());
    _setDigits(widget.value.replaceAll(RegExp(r'\D'), ''));
  }

  @override
  void didUpdateWidget(covariant CardNumberBoxes oldWidget) {
    super.didUpdateWidget(oldWidget);
    final displayed = _controllers.map((controller) => controller.text).join();
    final incoming = widget.value.replaceAll(RegExp(r'\D'), '');
    if (displayed != incoming || oldWidget.maxLength != widget.maxLength) {
      _setDigits(incoming.substring(
          0, incoming.length.clamp(0, widget.maxLength).toInt()));
    }
  }

  void _setDigits(String digits) {
    final limited =
        digits.substring(0, digits.length.clamp(0, widget.maxLength).toInt());
    for (var i = 0; i < 4; i++) {
      final start = i * 4;
      final end = (start + 4).clamp(0, limited.length).toInt();
      _controllers[i].text =
          start < limited.length ? limited.substring(start, end) : '';
    }
  }

  void _changed(int index, String value) {
    widget.onChanged(_controllers.map((controller) => controller.text).join());
    final slotLength = (widget.maxLength - index * 4).clamp(0, 4).toInt();
    if (value.length == slotLength && index < 3) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Card number', style: TextStyle(fontSize: 14)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: widget.onToggleVisibility,
                icon: HugeIcon(
                    icon: widget.obscure
                        ? HugeIcons.strokeRoundedEye
                        : HugeIcons.strokeRoundedEyeOff),
              ),
            ],
          ),
          Row(
            children: List.generate(4, (index) {
              final slotLength =
                  (widget.maxLength - index * 4).clamp(0, 4).toInt();
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 3 ? 0 : 8),
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    enabled: slotLength > 0,
                    obscureText: widget.obscure,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: slotLength,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(slotLength),
                    ],
                    onChanged: (value) => _changed(index, value),
                    decoration: InputDecoration(
                      hintText: List.filled(slotLength, '•').join(),
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      );
}
