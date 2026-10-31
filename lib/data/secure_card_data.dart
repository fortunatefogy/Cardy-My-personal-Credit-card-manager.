import 'dart:convert';

import 'package:flutter/services.dart';

/// Encrypts the PAN and expiry with the Android Keystore before local storage.
class SecureCardData {
  static const _channel = MethodChannel('cardwise/secure_card_data');

  static Future<String> encryptText(String value) async =>
      (await _channel.invokeMethod<String>('encrypt', {
        'plaintext': value,
      }))!;

  static Future<String> decryptText(String payload) async =>
      (await _channel.invokeMethod<String>('decrypt', {
        'payload': payload,
      }))!;

  static Future<String> encrypt({
    required String number,
    required String expiry,
  }) async =>
      (await _channel.invokeMethod<String>('encrypt', {
        'plaintext': jsonEncode({'number': number, 'expiry': expiry}),
      }))!;

  static Future<Map<String, String>> decrypt(String payload) async {
    final plaintext = await _channel.invokeMethod<String>('decrypt', {
      'payload': payload,
    });
    final decoded = jsonDecode(plaintext!) as Map<String, dynamic>;
    final details = <String, String>{
      'number': decoded['number'] as String? ?? '',
      'expiry': decoded['expiry'] as String? ?? '',
    };
    if (decoded.containsKey('cvv')) {
      details['cvv'] = decoded['cvv'] as String? ?? '';
    }
    return details;
  }
}
