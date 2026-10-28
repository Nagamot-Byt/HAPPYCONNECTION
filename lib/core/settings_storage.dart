import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

/// Persistent user settings for MedLink Connect.
///
/// Non-sensitive data uses [SharedPreferences]. Sensitive fields
/// (`rdpUsername`, `rdpDomain`) are stored encrypted via
/// [FlutterSecureStorage] (DPAPI on Windows).
@lazySingleton
class SettingsStorage {
  final SharedPreferences prefs;
  final FlutterSecureStorage _secure;

  /// Cached secure values (loaded during [init]).
  String _rdpUsername = '';
  String _rdpDomain = '';

  SettingsStorage(this.prefs)
      : _secure = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          wOptions: WindowsOptions(),
        );

  /// Pre-loads encrypted fields into memory.
  Future<void> init() async {
    _rdpUsername = await _secure.read(key: 'rdpUsername') ?? '';
    _rdpDomain = await _secure.read(key: 'rdpDomain') ?? '';
  }

  /// Persists current in-memory values for sensitive fields.
  Future<void> save() async {
    await _secure.write(key: 'rdpUsername', value: _rdpUsername);
    await _secure.write(key: 'rdpDomain', value: _rdpDomain);
  }

  Future<void> clear() async {
    await prefs.clear();
    await _secure.deleteAll();
    _rdpUsername = '';
    _rdpDomain = '';
  }

  // --- Non-sensitive (SharedPreferences) ---

  String get gateway => prefs.getString('gateway') ?? '';
  set gateway(String value) => prefs.setString('gateway', value);

  String get interfaceName => prefs.getString('interfaceName') ?? '';
  set interfaceName(String value) => prefs.setString('interfaceName', value);

  String get hospitalSubnetsAsText =>
      prefs.getString('hospitalSubnetsAsText') ?? '';
  set hospitalSubnetsAsText(String value) =>
      prefs.setString('hospitalSubnetsAsText', value);

  String get rdpHost => prefs.getString('rdpHost') ?? '';
  set rdpHost(String value) => prefs.setString('rdpHost', value);

  int get rdpPort => prefs.getInt('rdpPort') ?? 3389;
  set rdpPort(int value) => prefs.setInt('rdpPort', value);

  String get rdpProfile => prefs.getString('rdpProfile') ?? 'adaptive';
  set rdpProfile(String value) => prefs.setString('rdpProfile', value);

  String get wifiSsid => prefs.getString('wifiSsid') ?? '';
  set wifiSsid(String value) => prefs.setString('wifiSsid', value);

  // --- Sensitive (FlutterSecureStorage — encrypted) ---

  String get rdpUsername => _rdpUsername;
  set rdpUsername(String value) => _rdpUsername = value;

  String get rdpDomain => _rdpDomain;
  set rdpDomain(String value) => _rdpDomain = value;
}
