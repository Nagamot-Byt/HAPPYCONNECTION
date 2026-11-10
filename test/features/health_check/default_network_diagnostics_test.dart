import 'dart:async';

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

  test('checkTcpPortDetailed keeps success and error tied to the probe',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'checkTcpPort');
      return 7;
    });

    final success = await diagnostics.checkTcpPortDetailed('10.0.0.1', 3389);

    expect(success.value, 7);
    expect(success.error, isNull);
    expect(success.succeeded, isTrue);
    expect(diagnostics.lastProbeError, isNull);
  });

  test('checkTcpPortDetailed reports its own timeout cause', () async {
    final fastDiagnostics = DefaultNetworkDiagnostics.withProbeTimeout(
      const Duration(milliseconds: 20),
    );
    messenger.setMockMethodCallHandler(channel, (call) {
      return Completer<int>().future;
    });

    final failure =
        await fastDiagnostics.checkTcpPortDetailed('10.0.0.1', 3389);

    expect(failure.value, isNull);
    expect(failure.error, 'timeout');
    expect(failure.succeeded, isFalse);
  });

  test('ping times out at the configured probe timeout', () async {
    final fastDiagnostics = DefaultNetworkDiagnostics.withProbeTimeout(
      const Duration(milliseconds: 20),
    );
    messenger.setMockMethodCallHandler(channel, (call) {
      return Completer<int>().future;
    });

    expect(await fastDiagnostics.ping('10.0.0.1'), isNull);
    expect(fastDiagnostics.lastProbeError, 'timeout');
  });

  test('checkTcpPort times out at the configured probe timeout', () async {
    final fastDiagnostics = DefaultNetworkDiagnostics.withProbeTimeout(
      const Duration(milliseconds: 20),
    );
    messenger.setMockMethodCallHandler(channel, (call) {
      return Completer<int>().future;
    });

    expect(await fastDiagnostics.checkTcpPort('10.0.0.1', 3389), isNull);
    expect(fastDiagnostics.lastProbeError, 'timeout');
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
