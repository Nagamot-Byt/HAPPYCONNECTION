import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';

class _FakeDiagnostics extends NetworkDiagnostics {
  _FakeDiagnostics({this.tcpValue, this.probeError});

  final int? tcpValue;
  final String? probeError;

  @override
  String? get lastProbeError => probeError;

  @override
  Future<String> flushDns() async => 'DNS flushed';

  @override
  Future<String> clearNetworkCaches() async => 'Caches cleared';

  @override
  Future<int?> ping(String host) async => null;

  @override
  Future<int?> checkTcpPort(String host, int port) async => tcpValue;
}

void main() {
  test('checkTcpPortDetailed pairs the value of a successful probe', () async {
    final diagnostics = _FakeDiagnostics(tcpValue: 42);

    final result = await diagnostics.checkTcpPortDetailed('192.168.1.10', 3389);

    expect(result.value, 42);
    expect(result.error, isNull);
    expect(result.succeeded, isTrue);
  });

  test('checkTcpPortDetailed keeps the cause of a failed probe', () async {
    final diagnostics =
        _FakeDiagnostics(tcpValue: null, probeError: 'tiempo agotado');

    final result = await diagnostics.checkTcpPortDetailed('192.168.1.10', 3389);

    expect(result.value, isNull);
    expect(result.error, 'tiempo agotado');
    expect(result.succeeded, isFalse);
  });
}
