import 'package:animated_custom_dropdown/custom_dropdown.dart';
import 'package:flutter/material.dart';

import '../theme/cardy_palette.dart';

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.items,
    this.initialItem,
    this.labelText,
    this.hintText,
    this.validator,
    this.itemLabel,
    this.onChanged,
  });

  final List<T> items;
  final T? initialItem;
  final String? labelText;
  final String? hintText;
  final String? Function(T?)? validator;
  final String Function(T item)? itemLabel;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) => CustomDropdown<T>(
        items: items,
        initialItem: initialItem,
        labelText: labelText,
        hintText: hintText,
        validator: validator,
        onChanged: onChanged,
        listItemBuilder: itemLabel == null
            ? null
            : (context, item, isSelected, onItemSelect) => InkWell(
                  onTap: onItemSelect,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      itemLabel!(item),
                      style: TextStyle(
                        color: ink,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
        headerBuilder: itemLabel == null
            ? null
            : (context, selected, enabled) => Text(
                  itemLabel!(selected),
                  style: TextStyle(color: ink),
                ),
        decoration: CustomDropdownDecoration(
          closedFillColor: softSurface,
          expandedFillColor: surface,
          closedBorder: Border.all(color: Colors.transparent),
          closedBorderRadius: BorderRadius.circular(18),
          expandedBorder: Border.all(color: panelBorder),
          expandedBorderRadius: BorderRadius.circular(18),
          closedSuffixIcon:
              Icon(Icons.keyboard_arrow_down_rounded, color: muted),
          expandedSuffixIcon:
              Icon(Icons.keyboard_arrow_up_rounded, color: muted),
          hintStyle: TextStyle(color: muted),
          labelStyle: TextStyle(color: muted),
          floatingLabelStyle:
              TextStyle(color: ink, fontWeight: FontWeight.w600),
          headerStyle: TextStyle(color: ink),
          listItemStyle: TextStyle(color: ink),
        ),
      );
}
