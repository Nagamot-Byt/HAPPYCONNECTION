import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:medlink_connect/core/settings_storage.dart';

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

    settings.gateway = '192.168.1.1';
    settings.preferMostStableServer = false;
    settings.rdpUsername = 'medico1';
    settings.rdpDomain = 'HUV';
    await settings.save();

    expect(settings.gateway, '192.168.1.1');
    expect(settings.preferMostStableServer, isFalse);
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
}
