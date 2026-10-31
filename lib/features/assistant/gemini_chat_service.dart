import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/secure_card_data.dart';
import '../cards/card_catalogue.dart';
import '../cards/card_catalogue_service.dart';
import '../cards/credit_card.dart';

class GeminiChatService {
  GeminiChatService._();
  static final instance = GeminiChatService._();
  static const _encryptedKeyName = 'gemini_api_key_encrypted';
  static const _model = 'gemini-3.5-flash-lite';

  Future<void> saveApiKey(String key) async {
    final encrypted = await SecureCardData.encryptText(key.trim());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_encryptedKeyName, encrypted);
  }

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = prefs.getString(_encryptedKeyName);
    if (encrypted == null || encrypted.isEmpty) return null;
    return SecureCardData.decryptText(encrypted);
  }

  Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_encryptedKeyName);
  }

  Future<String> reply({
    required String apiKey,
    required List<CreditCard> cards,
    required List<({String role, String text})> history,
    List<CardCatalogEntry> catalogue = const [],
  }) async {
    final cardContext = cards.isEmpty
        ? 'No saved cards are available.'
        : cards
            .map((card) => [
                  'Bank: ${card.bank}',
                  'Card: ${card.nickname.isEmpty ? card.name : card.nickname} (${card.name})',
                  'Network: ${card.network}',
                  'Annual fee: ₹${card.annualFee}',
                  'Cashback rate: ${card.cashback}%',
                  'Reward rate: ${card.rewardRate} points per ₹100',
                  'Estimated point value: ₹${card.pointValue}',
                  'Categories: ${card.categories}',
                  'Status: ${card.active ? 'active' : 'inactive'}',
                ].join('\n'))
            .join('\n\n');
    final catalogueContext = _catalogueContext(cards, catalogue);

    var recentHistory =
        history.skipWhile((message) => message.role != 'user').toList();
    if (recentHistory.length > 16) {
      var start = recentHistory.length - 16;
      if (recentHistory[start].role != 'user') start++;
      recentHistory = recentHistory.sublist(start);
    }
    final contents = recentHistory
        .map((message) => {
              'role': message.role == 'assistant' ? 'model' : 'user',
              'parts': [
                {'text': message.text}
              ],
            })
        .toList();
    if (contents.isEmpty || contents.last['role'] != 'user') {
      throw const GeminiChatException(
          'Send a message to start the conversation.');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models/$_model:generateContent',
      );
      final request =
          await client.postUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.contentType = ContentType.json;
      request.headers.set('x-goog-api-key', apiKey);
      request.write(jsonEncode({
        'systemInstruction': {
          'parts': [
            {
              'text':
                  '''You are Cardy, a helpful assistant for an Indian user who manages credit cards in this app. Answer general questions using your general knowledge, including questions about purchases, travel, movies, shopping, and how to use card benefits.

There are two data sections:
1. Saved card profiles — the user's own card benefit settings. Treat these as the user's authoritative data for their cards.
2. CardTrail catalogue reference — data scraped from cardtrail.in. For each saved card there may be a matched catalogue block with field-by-field details and a checked date; after that there is a one-line index of the wider catalogue of Indian credit cards.

When a user asks which card to use for a purchase (movies, flights, groceries, travel and so on): first reason from their saved cards together with the matched CardTrail details, picking the card that best fits the spending category, reward rate, point value, and fees. If none of the saved cards fit well, you may compare against the wider catalogue index to suggest a better card, clearly saying it is a card they do not have yet.

Treat the saved benefit settings as overriding the CardTrail catalogue when they differ. When quoting catalogue specifics, cite the checked date if shown. Never claim a merchant offer or discount is active; describe only what the card's standing earning structure implies and label merchant offers as "worth double-checking". Do not claim a currently active offer, or invent specific bank benefits, fees, caps, exclusions, or eligibility rules beyond the sections below. If the user asks about a current offer or a benefit not included below, explain that you cannot verify it live and suggest checking the bank or merchant terms. If the data is insufficient for a reliable comparison, say what is missing. For savings comparisons, show a simple calculation from the sections below and remind the user that caps, exclusions, and offer eligibility may not be represented. Do not ask for, repeat, or infer full card numbers, expiry dates, CVVs, PINs, or OTPs. Be concise, friendly, and answer the user's actual question directly.

Saved card profiles:
$cardContext

$catalogueContext''',
            }
          ],
        },
        'contents': contents,
        'generationConfig': {
          'temperature': 0.4,
          'maxOutputTokens': 900,
        },
      }));

      final response =
          await request.close().timeout(const Duration(seconds: 60));
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded['error'] is Map
            ? (decoded['error'] as Map)['message']?.toString()
            : null;
        throw GeminiChatException(
            message ?? 'Gemini returned HTTP ${response.statusCode}.');
      }
      final candidates = decoded['candidates'] as List? ?? const [];
      if (candidates.isEmpty) {
        throw const GeminiChatException(
            'Gemini did not return a response. Try rephrasing your message.');
      }
      final content = (candidates.first as Map)['content'] as Map?;
      final parts = content?['parts'] as List? ?? const [];
      final answer = parts
          .whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .where((text) => text.isNotEmpty)
          .join('\n');
      if (answer.isEmpty)
        throw const GeminiChatException('Gemini returned an empty response.');
      return answer;
    } on SocketException {
      throw const GeminiChatException(
          'Could not connect. Check your internet connection.');
    } on HttpException catch (error) {
      throw GeminiChatException(error.message);
    } finally {
      client.close(force: true);
    }
  }

  static String _catalogueContext(
      List<CreditCard> cards, List<CardCatalogEntry> catalogue) {
    if (catalogue.isEmpty) {
      return 'CardTrail catalogue reference: not available right now.';
    }
    final blocks = <String>[];
    for (final card in cards) {
      final entry = matchCatalogueEntry(card, catalogue);
      final title = card.nickname.isEmpty ? card.name : card.nickname;
      if (entry == null) {
        blocks
            .add('Saved card "$title": no matching CardTrail catalogue entry.');
        continue;
      }
      blocks.add([
        'Saved card "$title" matches CardTrail entry "${entry.name}" (${entry.bank}):',
        if (entry.category.isNotEmpty) 'Category: ${entry.category}',
        if (entry.summary.isNotEmpty) 'About: ${entry.summary}',
        for (final key in entry.details.keys) '$key: ${entry.details[key]}',
        if (_checkedLabel(entry) != null)
          'Checked: ${_checkedLabel(entry)} (dd/mm/yyyy)',
        'More: ${entry.detailUrl}',
      ].join('\n'));
    }
    final index = catalogue
        .map((entry) => [
              '${entry.slug} — ${entry.name} (${entry.bank.isEmpty ? 'unlisted bank' : entry.bank})',
              if (entry.category.isNotEmpty) entry.category,
              if (entry.annualFee != null)
                'AF ₹${entry.annualFee!.toStringAsFixed(0)}',
              if (entry.forexMarkup != null)
                'fx ${entry.forexMarkup!.toStringAsFixed(entry.forexMarkup! == entry.forexMarkup!.roundToDouble() ? 0 : 1)}%',
              if (entry.cardTrailScore != null)
                'score ${entry.cardTrailScore!.toStringAsFixed(1)}',
            ].join(' | '))
        .join('\n');
    return [
      'CardTrail catalogue reference (data from cardtrail.in):',
      ...blocks,
      'Full catalogue index (one card per line: slug — name (bank) | category | annual fee | forex % | score):',
      index,
    ].join('\n\n');
  }

  static String? _checkedLabel(CardCatalogEntry entry) {
    final checked = entry.detailsCheckedAt ?? entry.checkedAt;
    if (checked == null) return null;
    final d = checked.day.toString().padLeft(2, '0');
    final m = checked.month.toString().padLeft(2, '0');
    return '$d/$m/${checked.year}';
  }

  static CardCatalogEntry? matchCatalogueEntry(
      CreditCard card, List<CardCatalogEntry> catalogue) {
    final cardBank =
        CardCatalogueService.bankFromText('${card.bank} ${card.name}');
    final cardTokens = _tokens('${card.bank} ${card.name}');
    if (cardTokens.isEmpty) return null;
    CardCatalogEntry? best;
    var bestScore = 0;
    for (final entry in catalogue) {
      final entryBank =
          CardCatalogueService.bankFromText('${entry.bank} ${entry.name}');
      if (cardBank.isNotEmpty &&
          entryBank.isNotEmpty &&
          cardBank != entryBank) {
        continue;
      }
      final entryTokens = _tokens('${entry.name} ${entry.slug} ${entry.bank}');
      var score = cardTokens.where(entryTokens.contains).length;
      final entryText = _normalize('${entry.name} ${entry.slug}');
      if (entryText.contains(_normalize(card.name))) score += 2;
      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }
    return bestScore >= 2 ? best : null;
  }

  static final _tokenRegExp = RegExp(r'[a-z0-9]+');

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static Set<String> _tokens(String text) => _tokenRegExp
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!)
      .toSet();
}

class GeminiChatException implements Exception {
  const GeminiChatException(this.message);
  final String message;
  @override
  String toString() => message;
}
