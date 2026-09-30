import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firestore_service.dart';
import 'security_service.dart';

/// Handles setting / verifying / changing the 4-digit Vault PIN.
/// The PIN hash is securely stored in hardware key storage via SecurityService.
class PinService {
  static const _legacyPinKey = 'vault_pin_hash';

  static String _hash(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  static Future<String?> _getStoredHash() async {
    // 1. Check hardware (on-device) storage first.
    String? hash = await SecurityService.instance.getVaultPinHash();
    if (hash != null && hash.isNotEmpty) {
      // Opportunistically ensure cloud backup is up-to-date
      FirestoreService.instance.saveVaultPinHash(hash).catchError((_) {});
      return hash;
    }

    // 2. Legacy migration check from SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    final legacyHash = prefs.getString(_legacyPinKey);
    if (legacyHash != null && legacyHash.isNotEmpty) {
      await SecurityService.instance.saveVaultPinHash(legacyHash);
      await prefs.remove(_legacyPinKey);
      FirestoreService.instance.saveVaultPinHash(legacyHash).catchError((_) {});
      return legacyHash;
    }

    // 3. Cloud fallback — used after logout/re-login or app reinstall when local storage was wiped.
    final cloudHash = await FirestoreService.instance.getVaultPinHash();
    if (cloudHash != null && cloudHash.isNotEmpty) {
      // Re-cache locally so subsequent lookups are fast.
      await SecurityService.instance.saveVaultPinHash(cloudHash);
      return cloudHash;
    }

    return null;
  }

  /// Syncs vault PIN hash between local storage and Firestore.
  static Future<void> syncFromCloud() async {
    try {
      // 1. If local PIN hash exists, ensure it is backed up to Firestore.
      final localHash = await SecurityService.instance.getVaultPinHash();
      if (localHash != null && localHash.isNotEmpty) {
        await FirestoreService.instance.saveVaultPinHash(localHash);
        return;
      }

      // 2. If no local PIN hash, fetch from Firestore and cache locally.
      final cloudHash = await FirestoreService.instance.getVaultPinHash();
      if (cloudHash != null && cloudHash.isNotEmpty) {
        await SecurityService.instance.saveVaultPinHash(cloudHash);
      }
    } catch (_) {}
  }

  static Future<bool> isPinSet() async {
    final hash = await _getStoredHash();
    return hash != null && hash.isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    final hash = _hash(pin);
    await SecurityService.instance.saveVaultPinHash(hash);
    // Cloud backup so the PIN survives logout and app uninstall/reinstall.
    try {
      await FirestoreService.instance.saveVaultPinHash(hash);
    } catch (_) {}
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = await _getStoredHash();
    if (stored == null) return false;
    return stored == _hash(pin);
  }

  /// Changes the PIN only if [oldPin] matches the currently stored one.
  static Future<bool> changePin(String oldPin, String newPin) async {
    final ok = await verifyPin(oldPin);
    if (!ok) return false;
    await setPin(newPin);
    return true;
  }

  /// Clears only the local device storage for the active session without touching
  /// the user's permanent vault PIN backup in Firestore. Called on logout.
  static Future<void> clearLocalCache() async {
    await SecurityService.instance.removeVaultPinHash();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyPinKey);
  }

  /// Clears the stored PIN from local storage AND from Firestore cloud backup.
  /// Called ONLY when user explicitly confirms "Forgot PIN -> Delete Vault & Reset".
  static Future<void> resetPin() async {
    await clearLocalCache();
    await FirestoreService.instance.removeVaultPinHash().catchError((_) {});
  }
}
