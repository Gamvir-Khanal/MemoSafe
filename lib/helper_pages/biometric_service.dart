import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps device biometric authentication (fingerprint / Face ID) for
/// unlocking the Vault. The app's own 4-digit PIN (see [PinService]) is
/// always the fallback — this only ever offers a faster path in, never
/// a replacement for it.
class BiometricService {
  BiometricService._();

  static final LocalAuthentication _auth = LocalAuthentication();
  static const _enabledKey = 'vault_biometric_enabled';

  /// Whether this device has biometric hardware set up at all (fingerprint
  /// enrolled, Face ID configured, etc). If false, there's nothing to
  /// offer and the UI should just go straight to the PIN.
  static Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck && supported;
    } catch (_) {
      return false;
    }
  }

  /// User's own preference for whether biometric unlock should be
  /// attempted. Defaults to on — devices without biometrics simply never
  /// see the prompt because [isAvailable] gates it first.
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  /// Shows the OS biometric prompt. Returns false — never throws — on
  /// any failure, cancellation, lockout, or unsupported device; callers
  /// should treat that as "fall back to PIN" rather than an error.
  static Future<bool> authenticate({
    String reason = 'Unlock your Vault',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
