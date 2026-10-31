import 'package:flutter_test/flutter_test.dart';

import 'package:cardy/features/assistant/gemini_chat_service.dart';
import 'package:cardy/features/cards/card_catalogue.dart';
import 'package:cardy/features/cards/credit_card.dart';

CardCatalogEntry entry(String slug, String name, String bank) =>
    CardCatalogEntry(
        slug: slug,
        name: name,
        bank: bank,
        detailUrl: 'https://c.in/cards/$slug/');

void main() {
  final catalogue = <CardCatalogEntry>[
    entry('hdfc-money-back-plus', 'HDFC Money Back Plus', 'HDFC Bank'),
    entry('hdfc-diners-club-black', 'HDFC Diners Club Black', 'HDFC Bank'),
    entry('axis-privilege', 'Axis Privilege', 'Axis Bank'),
    entry('sbi-cashback-card', 'SBI Cashback Card', 'SBI Card'),
  ];

  test('matches a saved card to its catalogue entry', () {
    final card = CreditCard(
        nickname: '',
        bank: 'HDFC',
        name: 'Diners Club Black',
        network: 'Mastercard');
    final match = GeminiChatService.matchCatalogueEntry(card, catalogue);
    expect(match, isNotNull);
    expect(match!.slug, 'hdfc-diners-club-black');
  });

  test('does not match across banks', () {
    final card = CreditCard(
        nickname: '', bank: 'Axis', name: 'Diners Club Black', network: 'Visa');
    expect(GeminiChatService.matchCatalogueEntry(card, catalogue), isNull);
  });

  test('prefers the closest name when several share a bank', () {
    final card = CreditCard(
        nickname: '',
        bank: 'HDFC Bank',
        name: 'HDFC Money Back',
        network: 'RuPay');
    final match = GeminiChatService.matchCatalogueEntry(card, catalogue);
    expect(match, isNotNull);
    expect(match!.slug, 'hdfc-money-back-plus');
  });

  test('returns null when nothing is similar', () {
    final card = CreditCard(
        nickname: '', bank: 'Kotak', name: 'Zen Venture', network: 'Visa');
    expect(GeminiChatService.matchCatalogueEntry(card, catalogue), isNull);
  });

  test('returns null with an empty catalogue', () {
    final card = CreditCard(
        nickname: '', bank: 'HDFC', name: 'Diners Club Black', network: 'Visa');
    expect(
        GeminiChatService.matchCatalogueEntry(card, const <CardCatalogEntry>[]),
        isNull);
  });
}
