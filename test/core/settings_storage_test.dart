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

    settings.gateway = '192.168.1.1';
    settings.rdpUsername = 'medico1';
    settings.rdpDomain = 'HUV';
    await settings.save();

    expect(settings.gateway, '192.168.1.1');
    expect(settings.rdpUsername, 'medico1');
    expect(settings.rdpDomain, 'HUV');

    await settings.clear();
    expect(settings.gateway, '');
    expect(settings.rdpUsername, '');
    expect(settings.rdpDomain, '');
  });
}
