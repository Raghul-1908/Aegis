import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String _pbkdf2(List<String> input) {
  final password = utf8.encode(input[0]);
  final salt = utf8.encode(input[1]);
  var block = Hmac(sha256, password).convert([...salt, 0, 0, 0, 1]).bytes;
  final result = List<int>.from(block);
  const iterations = 100000;
  for (var iteration = 1; iteration < iterations; iteration++) {
    block = Hmac(sha256, password).convert(block).bytes;
    for (var index = 0; index < result.length; index++) {
      result[index] ^= block[index];
    }
  }
  return base64UrlEncode(result);
}

bool _constantTimeEquals(String left, String right) {
  final leftBytes = utf8.encode(left);
  final rightBytes = utf8.encode(right);
  var difference = leftBytes.length ^ rightBytes.length;
  final length = leftBytes.length < rightBytes.length ? leftBytes.length : rightBytes.length;
  for (var index = 0; index < length; index++) {
    difference |= leftBytes[index] ^ rightBytes[index];
  }
  return difference == 0;
}

class AuthService {
  AuthService._();
  static final instance = AuthService._();
  final FlutterSecureStorage _storage = FlutterSecureStorage();

  static const _usernameKey = 'auth.username';
  static const _saltKey = 'auth.salt';
  static const _hashKey = 'auth.hash';

  Future<bool> hasAccount() async => await _storage.read(key: _usernameKey) != null;
  Future<String?> get username => _storage.read(key: _usernameKey);

  Future<String> _hash(String password, String salt) =>
      Isolate.run(() => _pbkdf2([password, salt]));

  String _generateSalt() => base64UrlEncode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)),
      );

  Future<void> createAccount(String username, String password) async {
    final user = username.trim();
    if (!RegExp(r'^[A-Za-z0-9_.-]{3,32}$').hasMatch(user)) {
      throw ArgumentError('Username must be 3-32 characters using letters, numbers, _, ., or -.');
    }
    if (password.length < 8 || password.length > 128) {
      throw ArgumentError('Password must be between 8 and 128 characters.');
    }
    final salt = _generateSalt();
    final hash = await _hash(password, salt);
    await _storage.write(key: _usernameKey, value: user);
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _hashKey, value: hash);
  }

  Future<bool> verify(String username, String password) async {
    final storedUser = await _storage.read(key: _usernameKey);
    final salt = await _storage.read(key: _saltKey);
    final storedHash = await _storage.read(key: _hashKey);
    if (storedUser == null || salt == null || storedHash == null) return false;
    final candidate = await _hash(password, salt);
    return storedUser == username.trim() && _constantTimeEquals(candidate, storedHash);
  }
}
