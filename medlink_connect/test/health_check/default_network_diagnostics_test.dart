import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/network_diagnostics_exception.dart';
import 'package:medlink_connect/features/health_check/default_network_diagnostics.dart';

void main() {
  late DefaultNetworkDiagnostics diagnostics;

  // Reusable mock channel that we reconfigure per-test.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    diagnostics = DefaultNetworkDiagnostics();
  });

  group('DefaultNetworkDiagnostics.flushDns', () {
    test('returns true when platform returns true', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          expect(call.method, 'flushDns');
          return true;
        },
      );

      final result = await diagnostics.flushDns();
      expect(result, true);
    });

    test('returns false when platform returns false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          expect(call.method, 'flushDns');
          return false;
        },
      );

      final result = await diagnostics.flushDns();
      expect(result, false);
    });

    test('returns false on MissingPluginException (channel not implemented)',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          throw MissingPluginException();
        },
      );

      final result = await diagnostics.flushDns();
      expect(result, false);
    });

    test('throws NetworkDiagnosticsException on elevation error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          throw PlatformException(
            code: 'elevation_required',
            message: 'Elevation required: needs Administrator privileges.',
          );
        },
      );

      expect(
        () => diagnostics.flushDns(),
        throwsA(isA<NetworkDiagnosticsException>()
            .having((e) => e.needsElevation, 'needsElevation', true)),
      );
    });

    test('returns false on generic PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          throw PlatformException(code: 'unknown', message: 'Something broke');
        },
      );

      final result = await diagnostics.flushDns();
      expect(result, false);
    });
  });

  group('DefaultNetworkDiagnostics.clearNetworkCaches', () {
    test('returns true on success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          expect(call.method, 'clearNetworkCaches');
          return true;
        },
      );

      final result = await diagnostics.clearNetworkCaches();
      expect(result, true);
    });

    test('throws on elevation error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          throw PlatformException(
            code: 'permission_denied',
            message: 'Permission denied. Run with sudo.',
          );
        },
      );

      expect(
        () => diagnostics.clearNetworkCaches(),
        throwsA(isA<NetworkDiagnosticsException>()
            .having((e) => e.needsElevation, 'needsElevation', true)),
      );
    });
  });

  group('DefaultNetworkDiagnostics.ping', () {
    test('returns latency as int when platform returns int', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          expect(call.method, 'ping');
          final args = call.arguments as Map;
          expect(args['host'], '8.8.8.8');
          return 42;
        },
      );

      final result = await diagnostics.ping('8.8.8.8');
      expect(result, 42);
    });

    test('returns null when platform returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async => null,
      );

      final result = await diagnostics.ping('10.255.255.1');
      expect(result, isNull);
    });

    test('passes count and timeoutMs parameters', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          final args = call.arguments as Map;
          expect(args['count'], 8);
          expect(args['timeoutMs'], 5000);
          return 10;
        },
      );

      final result = await diagnostics.ping('8.8.8.8',
          count: 8, timeoutMs: 5000);
      expect(result, 10);
    });

    test('retries once on first failure', () async {
      var callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          callCount++;
          if (callCount == 1) {
            return null; // First attempt fails
          }
          return 55; // Second attempt succeeds
        },
      );

      final result = await diagnostics.ping('8.8.8.8');
      expect(callCount, 2);
      expect(result, 55);
    });

    test('returns null when both attempts fail', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async => null,
      );

      final result = await diagnostics.ping('10.255.255.1');
      expect(result, isNull);
    });
  });

  group('DefaultNetworkDiagnostics.runFullDiagnostics', () {
    test('returns healthy result when everything succeeds', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          switch (call.method) {
            case 'flushDns':
              return true;
            case 'clearNetworkCaches':
              return true;
            case 'ping':
              return 13;
            default:
              return null;
          }
        },
      );

      final result = await diagnostics.runFullDiagnostics();
      expect(result.isHealthy, true);
      expect(result.dnsFlushed, true);
      expect(result.cachesCleared, true);
      expect(result.pingLatencyMs, 13);
      expect(result.pingError, isNull);
    });

    test('reports partial failure when DNS flush fails (without elevation)',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          switch (call.method) {
            case 'flushDns':
              return false;
            case 'clearNetworkCaches':
              return true;
            case 'ping':
              return 42;
            default:
              return null;
          }
        },
      );

      final result = await diagnostics.runFullDiagnostics();
      expect(result.isHealthy, false);
      expect(result.dnsFlushed, false);
      expect(result.cachesCleared, true);
      expect(result.pingLatencyMs, 42);
    });

    test('reports ping failure', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          switch (call.method) {
            case 'flushDns':
              return true;
            case 'clearNetworkCaches':
              return true;
            case 'ping':
              return null; // host unreachable
            default:
              return null;
          }
        },
      );

      final result = await diagnostics.runFullDiagnostics();
      expect(result.isHealthy, false);
      expect(result.pingLatencyMs, isNull);
    });

    test('never throws — captures all errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async {
          throw Exception('Boom!');
        },
      );

      final result = await diagnostics.runFullDiagnostics();
      // Should complete without throwing
      expect(result.dnsFlushed, false);
      expect(result.cachesCleared, false);
      expect(result.pingLatencyMs, isNull);
      expect(result.pingError, isNotNull);
    });

    test('summary produces Spanish text when requested', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async => true,
      );

      final result = await diagnostics.runFullDiagnostics();
      final spanish = result.summary(spanish: true);
      expect(spanish, contains('Red lista'));
    });

    test('summary produces English text by default', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.medlinkconnect/network_diagnostics'),
        (call) async => true,
      );

      final result = await diagnostics.runFullDiagnostics();
      final english = result.summary();
      expect(english, contains('Network ready'));
    });
  });
}
