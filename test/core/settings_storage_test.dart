import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medlink_connect/core/settings_storage.dart';

/// Secure storage backend that fails every read, simulating a missing
/// keyring/DPAPI backend on a locked-down hospital machine.
class _FailingSecureStorage extends FlutterSecureStoragePlatform {
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {}

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    throw PlatformException(
      code: 'storage_unavailable',
      message: 'no keyring available',
    );
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      false;

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      const {};

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('SettingsStorage defaults and persistence', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStorage(prefs);
    await settings.init();

    expect(settings.gateway, '');
    expect(settings.rdpPort, 3389);
    expect(settings.rdpProfile, 'adaptive');
    expect(settings.preferMostStableServer, isTrue);
    expect(settings.themeMode, ThemeMode.system);

    settings.gateway = '192.168.1.1';
    settings.preferMostStableServer = false;
    settings.themeMode = ThemeMode.dark;
    settings.rdpUsername = 'medico1';
    settings.rdpDomain = 'HUV';
    await settings.save();

    expect(settings.gateway, '192.168.1.1');
    expect(settings.preferMostStableServer, isFalse);
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.rdpUsername, 'medico1');
    expect(settings.rdpDomain, 'HUV');

    expect(settings.pendingSplitTunnelCleanup, isNull);
    await settings.setPendingSplitTunnelCleanup(
      subnets: ['10.0.0.0/8', '192.168.0.0/16'],
      gateway: '192.168.1.1',
      interfaceName: 'Wi-Fi',
    );
    final pending = settings.pendingSplitTunnelCleanup;
    expect(pending, isNotNull);
    expect(pending!.subnets, ['10.0.0.0/8', '192.168.0.0/16']);
    expect(pending.gateway, '192.168.1.1');
    expect(pending.interfaceName, 'Wi-Fi');

    await settings.clearPendingSplitTunnelCleanup();
    expect(settings.pendingSplitTunnelCleanup, isNull);

    await settings.clear();
    expect(settings.gateway, '');
    expect(settings.preferMostStableServer, isTrue);
    expect(settings.rdpUsername, '');
    expect(settings.rdpDomain, '');
  });

  test('every network preference getter and setter round-trips', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStorage(prefs);

    expect(settings.interfaceName, '');
    settings.interfaceName = 'wlan0';
    expect(settings.interfaceName, 'wlan0');

    expect(settings.hospitalSubnetsAsText, '');
    settings.hospitalSubnetsAsText = '10.0.0.0/8\n192.168.0.0/16';
    expect(settings.hospitalSubnetsAsText, contains('192.168.0.0/16'));

    expect(settings.rdpHost, '');
    settings.rdpHost = '10.0.0.50';
    expect(settings.rdpHost, '10.0.0.50');

    expect(settings.rdpPort, 3389);
    settings.rdpPort = 3390;
    expect(settings.rdpPort, 3390);

    expect(settings.rdpProfile, 'adaptive');
    settings.rdpProfile = 'speed';
    expect(settings.rdpProfile, 'speed');

    expect(settings.wifiSsid, '');
    settings.wifiSsid = 'HUV_WIFI';
    expect(settings.wifiSsid, 'HUV_WIFI');

    expect(settings.selectedServerPresetId, 'manual');
    settings.selectedServerPresetId = 'pediatria';
    expect(settings.selectedServerPresetId, 'pediatria');
  });

  test('secure storage failures fall back to empty protected fields',
      () async {
    FlutterSecureStoragePlatform.instance = _FailingSecureStorage();
    addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));

    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStorage(prefs);

    await settings.init();

    expect(settings.rdpUsername, '');
    expect(settings.rdpDomain, '');
  });
}
