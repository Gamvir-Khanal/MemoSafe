import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecurityService {
  SecurityService._internal();
  static final SecurityService instance = SecurityService._internal();

  static const String _masterKeyAlias = 'hardware_master_encryption_key_v1';
  static const String _vaultPinKeyAlias = 'hardware_vault_pin_hash_v1';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  String? _cachedMasterKey;

  /// Retrieves or generates a 256-bit (32-byte) hardware-backed AES master key.
  Future<String> getMasterKey() async {
    if (_cachedMasterKey != null) return _cachedMasterKey!;

    String? key = await _secureStorage.read(key: _masterKeyAlias);
    if (key == null || key.isEmpty) {
      final random = Random.secure();
      final values = List<int>.generate(32, (i) => random.nextInt(256));
      key = base64UrlEncode(values);
      await _secureStorage.write(key: _masterKeyAlias, value: key);
    }
    _cachedMasterKey = key;
    return key;
  }

  /// Returns the password key formatted for database encryption (sqflite_sqlcipher).
  Future<String> getDatabaseKey() async {
    return await getMasterKey();
  }

  /// Encrypts raw binary data (e.g. image, audio, drawing) using AES-256-CBC.
  /// Result format: 16-byte random IV + CipherText bytes.
  Future<Uint8List> encryptBytes(Uint8List plainBytes) async {
    final rawKey = await getMasterKey();
    final keyBytes = enc.Key.fromBase64(rawKey);
    final iv = enc.IV.fromSecureRandom(16);

    final encrypter = enc.Encrypter(enc.AES(keyBytes, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);

    final builder = BytesBuilder();
    builder.add(iv.bytes);
    builder.add(encrypted.bytes);
    return builder.toBytes();
  }

  /// Decrypts encrypted binary data (IV + CipherText).
  Future<Uint8List> decryptBytes(Uint8List encryptedBytes) async {
    if (encryptedBytes.length < 16) {
      // Return as is if not encrypted or invalid length
      return encryptedBytes;
    }

    try {
      final rawKey = await getMasterKey();
      final keyBytes = enc.Key.fromBase64(rawKey);
      final iv = enc.IV(encryptedBytes.sublist(0, 16));
      final cipherText = encryptedBytes.sublist(16);

      final encrypter = enc.Encrypter(enc.AES(keyBytes, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decryptBytes(enc.Encrypted(cipherText), iv: iv);
      return Uint8List.fromList(decrypted);
    } catch (_) {
      // Fallback if data was stored in plaintext before encryption was enabled
      return encryptedBytes;
    }
  }

  /// Reads a file from disk and decrypts it directly into memory.
  Future<Uint8List> decryptFile(File file) async {
    final bytes = await file.readAsBytes();
    return await decryptBytes(bytes);
  }

  /// Encrypts a file in place or to a target path.
  Future<void> encryptFile(File sourceFile, {File? targetFile}) async {
    if (!await sourceFile.exists()) return;
    final bytes = await sourceFile.readAsBytes();
    final encryptedBytes = await encryptBytes(bytes);
    final destination = targetFile ?? sourceFile;
    await destination.writeAsBytes(encryptedBytes, flush: true);
  }

  /// Hardware Vault PIN Storage
  Future<void> saveVaultPinHash(String hash) async {
    await _secureStorage.write(key: _vaultPinKeyAlias, value: hash);
  }

  Future<String?> getVaultPinHash() async {
    return await _secureStorage.read(key: _vaultPinKeyAlias);
  }

  Future<void> removeVaultPinHash() async {
    await _secureStorage.delete(key: _vaultPinKeyAlias);
  }
}
