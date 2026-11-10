import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/features/wifi/default_wifi_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DefaultWifiManager wifiManager;
  final log = <MethodCall>[];

  const channel = MethodChannel('com.medlinkconnect/wifi_manager');

  setUp(() {
    log.clear();
    wifiManager = DefaultWifiManager();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'scanNetworks':
          return <dynamic>['HUV_WIFI', 'Invitados_HUV'];
        case 'connect':
          return 'Conectado a HUV_WIFI';
        case 'getCurrentInfo':
          return <dynamic, dynamic>{
            'ssid': 'HUV_WIFI',
            'interfaceName': 'wlan0',
            'gateway': '192.168.5.1',
          };
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('scanNetworks', () {
    test('returns the native list of SSIDs', () async {
      final networks = await wifiManager.scanNetworks();
      expect(networks, equals(['HUV_WIFI', 'Invitados_HUV']));
      expect(log.single.method, equals('scanNetworks'));
    });

    test('falls back to an empty list on null results', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      final networks = await wifiManager.scanNetworks();
      expect(networks, isEmpty);
    });

    test('maps platform failures to a typed exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'scan_fail', message: 'x'),
      );

      await expectLater(
        wifiManager.scanNetworks(),
        throwsA(
          predicate(
            (error) =>
                error is WifiConnectionException &&
                error.message.contains('scan_fail'),
          ),
        ),
      );
    });
  });

  group('connect', () {
    test('forwards ssid and password through the channel', () async {
      final result = await wifiManager.connect(
        ssid: 'HUV_WIFI',
        password: 'secreto',
      );

      expect(result, equals('Conectado a HUV_WIFI'));
      expect(log.single.method, equals('connect'));
      final args = log.single.arguments as Map<Object?, Object?>;
      expect(args['ssid'], equals('HUV_WIFI'));
      expect(args['password'], equals('secreto'));
    });

    test('sends a null password when omitted', () async {
      await wifiManager.connect(ssid: 'HUV_WIFI');

      final args = log.single.arguments as Map<Object?, Object?>;
      expect(args['password'], isNull);
    });

    test('falls back to a default message on null results', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      final result = await wifiManager.connect(ssid: 'HUV_WIFI');
      expect(result, equals('Solicitud de conexión Wi-Fi enviada.'));
    });

    test('maps platform failures to a typed exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'conn_fail', message: 'x'),
      );

      await expectLater(
        wifiManager.connect(ssid: 'HUV_WIFI'),
        throwsA(
          predicate(
            (error) =>
                error is WifiConnectionException &&
                error.message.contains('conn_fail'),
          ),
        ),
      );
    });
  });

  group('getCurrentConnectionInfo', () {
    test('maps the native payload into WifiConnectionInfo', () async {
      final info = await wifiManager.getCurrentConnectionInfo();

      expect(info.ssid, equals('HUV_WIFI'));
      expect(info.interfaceName, equals('wlan0'));
      expect(info.gateway, equals('192.168.5.1'));
      expect(info.isConnected, isTrue);
      expect(log.single.method, equals('getCurrentInfo'));
    });

    test('falls back to an empty info on null results', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      final info = await wifiManager.getCurrentConnectionInfo();
      expect(info.ssid, isEmpty);
      expect(info.interfaceName, isEmpty);
      expect(info.gateway, isEmpty);
      expect(info.isConnected, isFalse);
    });

    test('fills missing fields with empty defaults', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (_) async => <dynamic, dynamic>{'ssid': 'HUV_WIFI'},
      );

      final info = await wifiManager.getCurrentConnectionInfo();
      expect(info.ssid, equals('HUV_WIFI'));
      expect(info.interfaceName, isEmpty);
      expect(info.gateway, isEmpty);
    });

    test('maps platform failures to a typed exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'info_fail', message: 'x'),
      );

      await expectLater(
        wifiManager.getCurrentConnectionInfo(),
        throwsA(
          predicate(
            (error) =>
                error is WifiConnectionException &&
                error.message.contains('info_fail'),
          ),
        ),
      );
    });
  });
}
