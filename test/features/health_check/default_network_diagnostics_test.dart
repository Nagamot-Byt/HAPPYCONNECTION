import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/features/health_check/default_network_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.medlinkconnect/network_diagnostics');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late DefaultNetworkDiagnostics diagnostics;

  setUp(() {
    diagnostics = DefaultNetworkDiagnostics();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('ping returns latency and clears the probe error', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ping');
      expect(call.arguments, {'host': '10.0.0.1'});
      return 12;
    });

    expect(await diagnostics.ping('10.0.0.1'), 12);
    expect(diagnostics.lastProbeError, isNull);
  });

  test('ping records the platform error instead of hiding it', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'inaccesible', message: 'sin ruta');
    });

    expect(await diagnostics.ping('10.0.0.1'), isNull);
    expect(diagnostics.lastProbeError, 'inaccesible: sin ruta');
  });

  test('checkTcpPort records the platform error', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'timeout', message: 'agotado');
    });

    expect(await diagnostics.checkTcpPort('10.0.0.1', 3389), isNull);
    expect(diagnostics.lastProbeError, 'timeout: agotado');
  });

  test('flushDns maps permission errors to a typed exception', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'permiso_denegado', message: 'UAC');
    });

    await expectLater(
      diagnostics.flushDns(),
      throwsA(isA<PrivilegeRequiredException>()),
    );
  });

  test('clearNetworkCaches keeps non-permission errors as diagnostics',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'arp_error', message: 'sin interfaces');
    });

    await expectLater(
      diagnostics.clearNetworkCaches(),
      throwsA(isA<NetworkDiagnosticException>()),
    );
  });
}
