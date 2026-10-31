import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'credit_card.dart';
import '../../theme/cardy_palette.dart';

class CardSearchDelegate extends SearchDelegate<CreditCard?> {
  CardSearchDelegate(this.cards);
  final List<CreditCard> cards;
  @override
  String get searchFieldLabel => 'Search cards and benefits';
  @override
  List<Widget> buildActions(BuildContext c) => [
        IconButton(
            onPressed: () => query = '',
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01)),
      ];
  @override
  Widget buildLeading(BuildContext c) => IconButton(
        onPressed: () => close(c, null),
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01),
      );
  @override
  Widget buildResults(BuildContext c) => buildSuggestions(c);
  @override
  Widget buildSuggestions(BuildContext c) {
    final q = query.toLowerCase();
    final matches = cards
        .where(
          (x) => '${x.bank} ${x.name} ${x.nickname} ${x.categories} ${x.notes}'
              .toLowerCase()
              .contains(q),
        )
        .toList();
    return ListView(
      children: matches
          .map(
            (x) => ListTile(
              leading: HugeIcon(
                  icon: HugeIcons.strokeRoundedCreditCard, color: accentColor),
              title: Text(x.nickname.isEmpty ? x.name : x.nickname),
              subtitle: Text('${x.bank} · ${x.categories}'),
              onTap: () {
                close(c, x);
              },
            ),
          )
          .toList(),
    );
  }
}
