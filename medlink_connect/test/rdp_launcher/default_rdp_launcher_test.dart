import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/rdp_connection_profile.dart';
import 'package:medlink_connect/core/rdp_launch_result.dart';
import 'package:medlink_connect/features/rdp_launcher/default_rdp_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock the platform channel so tests don't crash.
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/rdp_launcher'),
      (MethodCall call) async {
        return null;
      },
    );
    // Mock url_launcher channel to avoid MissingPluginException.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (MethodCall call) async {
        if (call.method == 'canLaunch') return false;
        if (call.method == 'launch') return true;
        return null;
      },
    );
  });
  late DefaultRdpLauncher launcher;
  late RdpConnectionProfile basicProfile;

  setUp(() {
    launcher = DefaultRdpLauncher();
    basicProfile = RdpConnectionProfile(
      name: 'Test Server',
      address: '10.0.0.100',
      port: 3389,
      username: 'doctor1',
    );
  });

  group('URI construction', () {
    test('builds basic URI with all standard parameters', () {
      final uri = launcher.buildRdpUriForTest(basicProfile);

      expect(uri.scheme, 'rdp');
      expect(uri.query, contains('full%20address=s:10.0.0.100:3389'));
      expect(uri.query, contains('username=s:doctor1'));
      expect(uri.query, contains('audiomode=i:2'));
      expect(uri.query, contains('redirectclipboard=i:1'));
      expect(uri.query, contains('autoreconnection%20enabled=i:1'));
      expect(uri.query, contains('connection%20type=i:6'));
    });

    test('omits username when null', () {
      final profile = RdpConnectionProfile(
        name: 'No User',
        address: '192.168.1.1',
      );
      final uri = launcher.buildRdpUriForTest(profile);

      expect(uri.query, isNot(contains('username')));
    });

    test('omits username when empty string', () {
      final profile = RdpConnectionProfile(
        name: 'Empty User',
        address: '192.168.1.1',
        username: '',
      );
      final uri = launcher.buildRdpUriForTest(profile);

      expect(uri.query, isNot(contains('username')));
    });

    test('handles non-default port', () {
      final profile = RdpConnectionProfile(
        name: 'Custom Port',
        address: '10.0.0.100',
        port: 3390,
      );
      final uri = launcher.buildRdpUriForTest(profile);

      expect(uri.query, contains('full%20address=s:10.0.0.100:3390'));
    });

    test('handles hostname (FQDN)', () {
      final profile = RdpConnectionProfile(
        name: 'Hostname',
        address: 'serv-ginecologico.huv.gov.co',
      );
      final uri = launcher.buildRdpUriForTest(profile);

      expect(
        uri.query,
        contains('full%20address=s:serv-ginecologico.huv.gov.co:3389'),
      );
    });

    test('handles IPv6 address', () {
      final profile = RdpConnectionProfile(
        name: 'IPv6',
        address: '2001:db8::1',
      );
      final uri = launcher.buildRdpUriForTest(profile);

      // IPv6 addresses are URI-encoded but should remain intact
      expect(uri.query, contains('2001:db8'));
    });

    test('handles IPv6 with brackets', () {
      final profile = RdpConnectionProfile(
        name: 'IPv6 Bracketed',
        address: '[2001:db8::1]',
      );
      final uri = launcher.buildRdpUriForTest(profile);

      expect(uri.query, contains('2001:db8'));
    });

    test('URI encoding preserves special characters in username', () {
      final profile = RdpConnectionProfile(
        name: 'Special',
        address: '10.0.0.100',
        username: 'DOMINIO\\usuario',
      );
      final uri = launcher.buildRdpUriForTest(profile);

      // Backslash should be percent-encoded
      expect(uri.query, contains('username=s:DOMINIO%5Cusuario'));
    });

    test('URI encoding preserves spaces in username', () {
      final profile = RdpConnectionProfile(
        name: 'Space User',
        address: '10.0.0.100',
        username: 'Dr Garcia',
      );
      final uri = launcher.buildRdpUriForTest(profile);

      expect(uri.query, contains('username=s:Dr%20Garcia'));
    });
  });

  group('Profile management', () {
    test('starts with empty profiles', () {
      expect(launcher.profiles, isEmpty);
    });

    test('saveProfile adds a profile', () {
      launcher.saveProfile(basicProfile);
      expect(launcher.profiles.length, 1);
      expect(launcher.profiles.first.name, 'Test Server');
    });

    test('saveProfile updates existing profile by name', () {
      launcher.saveProfile(basicProfile);
      final updated = RdpConnectionProfile(
        name: 'Test Server',
        address: '10.0.0.200',
        port: 3390,
      );
      launcher.saveProfile(updated);

      expect(launcher.profiles.length, 1);
      expect(launcher.profiles.first.address, '10.0.0.200');
      expect(launcher.profiles.first.port, 3390);
    });

    test('loadProfiles replaces the list', () {
      launcher.saveProfile(basicProfile);
      launcher.loadProfiles([
        RdpConnectionProfile(name: 'A', address: '10.0.0.1'),
        RdpConnectionProfile(name: 'B', address: '10.0.0.2'),
      ]);

      expect(launcher.profiles.length, 2);
    });

    test('removeProfile removes by name', () {
      launcher.saveProfile(basicProfile);
      final removed = launcher.removeProfile('Test Server');

      expect(removed, isTrue);
      expect(launcher.profiles, isEmpty);
    });

    test('removeProfile returns false for unknown name', () {
      final removed = launcher.removeProfile('Unknown');
      expect(removed, isFalse);
    });

    test('findProfile returns profile by name', () {
      launcher.saveProfile(basicProfile);
      final found = launcher.findProfile('Test Server');

      expect(found, isNotNull);
      expect(found!.address, '10.0.0.100');
    });

    test('findProfile returns null for unknown name', () {
      final found = launcher.findProfile('Unknown');
      expect(found, isNull);
    });
  });

  group('launchRdp validation', () {
    test('returns invalidConfiguration for empty address', () async {
      final result = await launcher.launchRdp(address: '');

      expect(result.success, isFalse);
      expect(result.errorCode, 'RDP_INVALID_CONFIG');
      expect(result.message, contains('inválida'));
    });

    test('returns invalidConfiguration for port 0', () async {
      final result = await launcher.launchRdp(address: '10.0.0.1', port: 0);

      expect(result.success, isFalse);
      expect(result.errorCode, 'RDP_INVALID_CONFIG');
    });

    test('returns invalidConfiguration for port > 65535', () async {
      final result =
          await launcher.launchRdp(address: '10.0.0.1', port: 99999);

      expect(result.success, isFalse);
      expect(result.errorCode, 'RDP_INVALID_CONFIG');
    });

    test('profile takes precedence over individual params', () async {
      launcher.saveProfile(basicProfile);

      // profile.address is 10.0.0.100 — this should be used, not 192.168.1.1
      // However, since isRdpClientAvailable returns false in test
      // (no real platform), we expect clientNotFound.
      final result = await launcher.launchRdp(
        address: '192.168.1.1',
        profile: basicProfile,
      );

      // In test environment without an RDP client: clientNotFound
      expect(result.errorCode, 'RDP_CLIENT_NOT_FOUND');
    });
  });

  group('RdpLaunchResult factories', () {
    test('connected creates success result', () {
      final result = RdpLaunchResult.connected();
      expect(result.success, isTrue);
      expect(result.message, '✅ Conectado');
      expect(result.errorCode, isNull);
    });

    test('clientNotFound creates failure result', () {
      final result = RdpLaunchResult.clientNotFound();
      expect(result.success, isFalse);
      expect(result.errorCode, 'RDP_CLIENT_NOT_FOUND');
      expect(result.message, contains('Cliente RDP no encontrado'));
    });

    test('launchFailed creates result with detail', () {
      final result = RdpLaunchResult.launchFailed('timeout');
      expect(result.success, isFalse);
      expect(result.errorCode, 'RDP_LAUNCH_FAILED');
      expect(result.message, contains('timeout'));
    });

    test('invalidConfiguration creates result with detail', () {
      final result = RdpLaunchResult.invalidConfiguration('port 0');
      expect(result.success, isFalse);
      expect(result.errorCode, 'RDP_INVALID_CONFIG');
      expect(result.message, contains('port 0'));
    });

    test('preLaunchDenied creates result with reason', () {
      final result = RdpLaunchResult.preLaunchDenied('VPN required');
      expect(result.success, isFalse);
      expect(result.errorCode, 'RDP_PRELAUNCH_DENIED');
      expect(result.message, contains('VPN required'));
    });

    test('preLaunchDenied null reason uses default', () {
      final result = RdpLaunchResult.preLaunchDenied(null);
      expect(result.message, contains('rechazada'));
    });
  });

  group('RdpLaunchResult equality', () {
    test('identical results are equal', () {
      expect(RdpLaunchResult.connected(), RdpLaunchResult.connected());
    });

    test('different results are not equal', () {
      expect(
        RdpLaunchResult.connected(),
        isNot(RdpLaunchResult.clientNotFound()),
      );
    });
  });
}
