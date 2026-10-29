import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

/// Rutas que la aplicación agregó y que deben retirarse si el cierre
/// anterior no pudo completar la limpieza.
class PendingSplitTunnelCleanup {
  const PendingSplitTunnelCleanup({
    required this.subnets,
    required this.gateway,
    required this.interfaceName,
  });

  final List<String> subnets;
  final String gateway;
  final String interfaceName;
}

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

  String get selectedServerPresetId =>
      prefs.getString('selectedServerPresetId') ?? 'manual';
  set selectedServerPresetId(String value) =>
      prefs.setString('selectedServerPresetId', value);

  bool get preferMostStableServer =>
      prefs.getBool('preferMostStableServer') ?? true;
  set preferMostStableServer(bool value) =>
      prefs.setBool('preferMostStableServer', value);

  PendingSplitTunnelCleanup? get pendingSplitTunnelCleanup {
    final rawSubnets = prefs.getString('pendingSplitTunnelSubnets') ?? '';
    final gateway = prefs.getString('pendingSplitTunnelGateway') ?? '';
    final interfaceName = prefs.getString('pendingSplitTunnelInterface') ?? '';
    final subnets = rawSubnets
        .split('\n')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (subnets.isEmpty || gateway.isEmpty || interfaceName.isEmpty) {
      return null;
    }
    return PendingSplitTunnelCleanup(
      subnets: subnets,
      gateway: gateway,
      interfaceName: interfaceName,
    );
  }

  Future<void> setPendingSplitTunnelCleanup({
    required List<String> subnets,
    required String gateway,
    required String interfaceName,
  }) async {
    await Future.wait([
      prefs.setString('pendingSplitTunnelSubnets', subnets.join('\n')),
      prefs.setString('pendingSplitTunnelGateway', gateway),
      prefs.setString('pendingSplitTunnelInterface', interfaceName),
    ]);
  }

  Future<void> clearPendingSplitTunnelCleanup() async {
    await Future.wait([
      prefs.remove('pendingSplitTunnelSubnets'),
      prefs.remove('pendingSplitTunnelGateway'),
      prefs.remove('pendingSplitTunnelInterface'),
    ]);
  }

  // --- Sensitive (FlutterSecureStorage — encrypted) ---

  String get rdpUsername => _rdpUsername;
  set rdpUsername(String value) => _rdpUsername = value;

  String get rdpDomain => _rdpDomain;
  set rdpDomain(String value) => _rdpDomain = value;
}
