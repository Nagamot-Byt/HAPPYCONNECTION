import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistent user settings for MedLink Connect.
///
/// Stores network configuration and RDP credentials (except passwords —
/// those are never persisted). Non-sensitive data backed by
/// [SharedPreferences]. Sensitive fields (`rdpUsername`, `rdpDomain`)
/// are encrypted via [FlutterSecureStorage].
class SettingsService {
  SettingsService(this._prefs)
      : _secure = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          wOptions: WindowsOptions(),
        );

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  /// Cached secure values.
  String _rdpUsername = '';
  String _rdpDomain = '';

  static const _kSubnets = 'medlink.hospitalSubnets';
  static const _kGateway = 'medlink.gateway';
  static const _kIface = 'medlink.interfaceName';
  static const _kWifiSsid = 'medlink.wifi.ssid';
  static const _kRdpHost = 'medlink.rdp.host';
  static const _kRdpPort = 'medlink.rdp.port';
  static const _kRdpProfile = 'medlink.rdp.profile';

  static const defaultSubnets = [
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16'
  ];
  static const defaultGateway = '192.168.1.1';
  static const defaultInterface = 'Wi-Fi';
  static const defaultRdpHost = 'serv_pediatrico.huv.gov.co';
  static const int defaultRdpPort = 3389;
  static const defaultRdpProfile = 'adaptive';

  /// Pre-loads encrypted fields into memory.
  Future<void> loadSecureFields() async {
    _rdpUsername = await _secure.read(key: 'medlink.rdp.username') ?? '';
    _rdpDomain = await _secure.read(key: 'medlink.rdp.domain') ?? '';
  }

  // --- Non-sensitive loaders ---
  List<String> get hospitalSubnets =>
      _prefs.getStringList(_kSubnets) ?? List.from(defaultSubnets);

  String get gateway => _prefs.getString(_kGateway) ?? defaultGateway;
  String get interfaceName => _prefs.getString(_kIface) ?? defaultInterface;
  String get wifiSsid => _prefs.getString(_kWifiSsid) ?? '';
  String get rdpHost => _prefs.getString(_kRdpHost) ?? defaultRdpHost;
  int get rdpPort => _prefs.getInt(_kRdpPort) ?? defaultRdpPort;
  String get rdpProfile => _prefs.getString(_kRdpProfile) ?? defaultRdpProfile;

  String get hospitalSubnetsAsText => hospitalSubnets.join('\n');

  // --- Sensitive (encrypted) ---
  String get rdpUsername => _rdpUsername;
  String get rdpDomain => _rdpDomain;

  // --- Savers ---
  Future<bool> setHospitalSubnets(List<String> value) async {
    return _prefs.setStringList(_kSubnets, List.unmodifiable(value));
  }

  Future<bool> setHospitalSubnetsFromText(String value) async {
    final lines = value
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    return setHospitalSubnets(lines);
  }

  Future<bool> setGateway(String value) => _prefs.setString(_kGateway, value);
  Future<bool> setInterfaceName(String value) =>
      _prefs.setString(_kIface, value);
  Future<bool> setWifiSsid(String value) => _prefs.setString(_kWifiSsid, value);
  Future<bool> setRdpHost(String value) => _prefs.setString(_kRdpHost, value);
  Future<bool> setRdpPort(int value) => _prefs.setInt(_kRdpPort, value);
  Future<bool> setRdpProfile(String value) =>
      _prefs.setString(_kRdpProfile, value);

  Future<void> setRdpUsername(String value) async {
    _rdpUsername = value;
    await _secure.write(key: 'medlink.rdp.username', value: value);
  }

  Future<void> setRdpDomain(String value) async {
    _rdpDomain = value;
    await _secure.write(key: 'medlink.rdp.domain', value: value);
  }

  /// Saves all fields from the UI form in a single pass.
  Future<void> saveAll({
    required String subnetsText,
    required String gateway,
    required String interfaceName,
    required String wifiSsid,
    required String rdpHost,
    required int rdpPort,
    required String rdpUsername,
    required String rdpDomain,
    required String rdpProfile,
  }) async {
    await Future.wait([
      setHospitalSubnetsFromText(subnetsText),
      setGateway(gateway),
      setInterfaceName(interfaceName),
      setWifiSsid(wifiSsid),
      setRdpHost(rdpHost),
      setRdpPort(rdpPort),
      setRdpUsername(rdpUsername),
      setRdpDomain(rdpDomain),
      setRdpProfile(rdpProfile),
    ]);
  }

  /// Clears persisted settings (returns to hard-coded defaults).
  Future<bool> clear() async {
    await _prefs.remove(_kSubnets);
    await _prefs.remove(_kGateway);
    await _prefs.remove(_kIface);
    await _prefs.remove(_kWifiSsid);
    await _prefs.remove(_kRdpHost);
    await _prefs.remove(_kRdpPort);
    await _prefs.remove(_kRdpProfile);
    await _secure.deleteAll();
    _rdpUsername = '';
    _rdpDomain = '';
    return true;
  }
}
