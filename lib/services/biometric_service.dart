import 'package:local_auth/local_auth.dart';

class BiometricService {
  BiometricService._();
  static final instance = BiometricService._();
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> get isSupported async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Aegis',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
