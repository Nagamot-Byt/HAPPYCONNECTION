import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureRdpStore {
  final FlutterSecureStorage _storage;
  const SecureRdpStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> savePassword(String id, String password) async {
    if (password.isEmpty) return;
    await _storage.write(key: 'rdp_pwd_$id', value: password);
  }

  Future<String?> getPassword(String id) async {
    return _storage.read(key: 'rdp_pwd_$id');
  }

  Future<void> deletePassword(String id) async {
    await _storage.delete(key: 'rdp_pwd_$id');
  }
}
