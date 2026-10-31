import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/secure_card_data.dart';
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
                  '''You are Cardy, a helpful assistant for an Indian user who manages credit cards in this app. Answer general questions using your general knowledge, including questions about purchases, travel, movies, shopping, and how to use card benefits. When a user asks which card to use, recommend only among the saved cards listed below and use their saved benefit settings as the reliable source for card-specific rates and terms. You may offer general context about common card or merchant practices, but label it as general guidance, not a verified benefit of a particular saved card. Do not claim that an offer is currently active, or invent specific bank benefits, fees, caps, exclusions, or eligibility rules. If the user asks about a current offer or a card-specific benefit not included below, explain that you cannot verify it live and suggest checking the bank or merchant terms. If the saved data is insufficient to make a reliable comparison, say what is missing. For savings comparisons, show a simple calculation from the saved rates and remind the user that caps, exclusions, and offer eligibility may not be represented. Do not ask for, repeat, or infer full card numbers, expiry dates, CVVs, PINs, or OTPs. Be concise, friendly, and answer the user's actual question directly.

Saved card profiles:
$cardContext''',
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
}

class GeminiChatException implements Exception {
  const GeminiChatException(this.message);
  final String message;
  @override
  String toString() => message;
}
