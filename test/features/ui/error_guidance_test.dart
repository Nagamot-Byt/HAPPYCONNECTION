import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations_es.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/features/ui/error_guidance.dart';

void main() {
  final resolver = ErrorGuidanceResolver(AppLocalizationsEs());

  group('ErrorGuidanceResolver', () {
    test('maps privilege platform errors to permission guidance', () {
      final guidance = resolver.resolve(
        PlatformException(code: 'permiso_denegado', message: 'root'),
      );

      expect(guidance.title, 'Faltan permisos de Administrador');
    });

    test('maps route platform errors to route guidance', () {
      final guidance = resolver.resolve(
        PlatformException(code: 'route_error', message: 'route add failed'),
      );

      expect(guidance.title, 'Problema con rutas/gateway');
    });

    test('maps argument errors and typed exceptions', () {
      expect(
        resolver.classify(ArgumentError('bad value')),
        MedLinkErrorType.validation,
      );
      expect(
        resolver.classify(
          const WifiConnectionException('no wifi'),
        ),
        MedLinkErrorType.wifi,
      );
    });

    test('falls back to generic guidance', () {
      final guidance = resolver.resolve(StateError('unexpected'));

      expect(guidance.title, 'La conexión no se completó');
      expect(guidance.bullets, isNotEmpty);
    });
  });
}
