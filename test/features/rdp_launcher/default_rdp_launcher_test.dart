import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/features/rdp_launcher/default_rdp_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DefaultRdpLauncher launcher;
  final log = <MethodCall>[];

  const channel = MethodChannel('com.medlinkconnect/rdp_launcher');

  setUp(() {
    log.clear();
    launcher = DefaultRdpLauncher();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'preLaunch':
          return true;
        case 'isRdpClientAvailable':
          return true;
        case 'launchRdp':
          return 'RDP lanzado';
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('preLaunch', () {
    test('returns the native result', () async {
      final result = await launcher.preLaunch();
      expect(result, isTrue);
      expect(log.single.method, equals('preLaunch'));
    });

    test('falls back to false on null results', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      expect(await launcher.preLaunch(), isFalse);
    });

    test('swallows platform exceptions', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'err', message: 'fallo'),
      );

      expect(await launcher.preLaunch(), isFalse);
    });
  });

  group('isRdpClientAvailable', () {
    test('returns the native result', () async {
      final result = await launcher.isRdpClientAvailable();
      expect(result, isTrue);
      expect(log.single.method, equals('isRdpClientAvailable'));
    });

    test('falls back to false on null results', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      expect(await launcher.isRdpClientAvailable(), isFalse);
    });

    test('swallows platform exceptions', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'err', message: 'fallo'),
      );

      expect(await launcher.isRdpClientAvailable(), isFalse);
    });

    test('swallows missing plugin exceptions', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException(),
      );

      expect(await launcher.isRdpClientAvailable(), isFalse);
    });
  });

  group('launchRdp', () {
    test('sends sanitized arguments through the channel', () async {
      final result = await launcher.launchRdp(
        host: '  192.168.1.10  ',
        port: 3390,
        username: ' dr.nurse ',
        domain: ' HUV ',
        useWebFeed: true,
        profile: 'speed',
        measuredLatencyMs: 42,
      );

      expect(result, equals('RDP lanzado'));
      expect(log.single.method, equals('launchRdp'));
      final args = log.single.arguments as Map<Object?, Object?>;
      expect(args['host'], equals('192.168.1.10'));
      expect(args['port'], equals(3390));
      expect(args['username'], equals('dr.nurse'));
      expect(args['domain'], equals('HUV'));
      expect(args['useWebFeed'], isTrue);
      expect(args['profile'], equals('speed'));
      expect(args['measuredLatencyMs'], equals(42));
    });

    test('uses documented defaults when optional args are omitted', () async {
      await launcher.launchRdp(host: '192.168.1.10');

      final args = log.single.arguments as Map<Object?, Object?>;
      expect(args['port'], equals(3389));
      expect(args['username'], isNull);
      expect(args['domain'], isNull);
      expect(args['useWebFeed'], isFalse);
      expect(args['profile'], equals('adaptive'));
      expect(args['measuredLatencyMs'], isNull);
    });

    test('falls back to a default message on null results', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      final result = await launcher.launchRdp(host: '192.168.1.10');
      expect(result, equals('Conexión RDP lanzada exitosamente.'));
    });

    test('rejects an empty host before touching the channel', () async {
      expect(
        () => launcher.launchRdp(host: '   '),
        throwsArgumentError,
      );
      expect(log, isEmpty);
    });

    test('rejects out-of-range ports before touching the channel', () async {
      expect(
        () => launcher.launchRdp(host: '192.168.1.10', port: 0),
        throwsArgumentError,
      );
      expect(
        () => launcher.launchRdp(host: '192.168.1.10', port: 65536),
        throwsArgumentError,
      );
      expect(log, isEmpty);
    });

    test('maps missing plugins to a typed exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException(),
      );

      await expectLater(
        launcher.launchRdp(host: '192.168.1.10'),
        throwsA(
          predicate(
            (error) =>
                error is RdpLaunchException &&
                error.message.contains('no está disponible'),
          ),
        ),
      );
    });

    test('wraps platform failures with code and message', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'rdp_fail', message: 'x'),
      );

      await expectLater(
        launcher.launchRdp(host: '192.168.1.10'),
        throwsA(
          predicate(
            (error) =>
                error is RdpLaunchException &&
                error.message.contains('rdp_fail') &&
                error.message.contains('x'),
          ),
        ),
      );
    });

    test('uses a fallback message when the platform error is empty',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'rdp_fail', message: ''),
      );

      await expectLater(
        launcher.launchRdp(host: '192.168.1.10'),
        throwsA(
          predicate(
            (error) =>
                error is RdpLaunchException &&
                error.message.contains('Error desconocido'),
          ),
        ),
      );
    });
  });
}
