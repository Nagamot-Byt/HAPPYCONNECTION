import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:medlink_connect/core/exceptions.dart';

class GuidanceContent {
  final String title;
  final List<String> bullets;

  const GuidanceContent({
    required this.title,
    required this.bullets,
  });
}

class ErrorGuidanceResolver {
  const ErrorGuidanceResolver(this.l10n);

  final AppLocalizations l10n;

  MedLinkErrorType classify(Object error) {
    if (error is MedLinkException) return error.type;
    if (error is ArgumentError) return MedLinkErrorType.validation;
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      if (code.contains('permiso') ||
          code.contains('privilege') ||
          code.contains('access_denied')) {
        return MedLinkErrorType.permission;
      }
      if (code.startsWith('wifi')) return MedLinkErrorType.wifi;
      if (code.startsWith('rdp')) return MedLinkErrorType.rdp;
      if (code.startsWith('route') || code.startsWith('arp')) {
        return MedLinkErrorType.route;
      }
      if (code.startsWith('flushdns') || code.startsWith('network')) {
        return MedLinkErrorType.network;
      }
    }
    return MedLinkErrorType.unknown;
  }

  GuidanceContent resolve(Object error) => resolveType(classify(error));

  GuidanceContent resolveType(MedLinkErrorType type) {
    return switch (type) {
      MedLinkErrorType.permission => GuidanceContent(
          title: l10n.guidanceAdminErrorTitle,
          bullets: [
            l10n.guidanceAdminErrorBullet1,
            l10n.guidanceAdminErrorBullet2,
            l10n.guidanceAdminErrorBullet3,
          ],
        ),
      MedLinkErrorType.wifi => GuidanceContent(
          title: l10n.guidanceWifiErrorTitle,
          bullets: [
            l10n.guidanceWifiErrorBullet1,
            l10n.guidanceWifiErrorBullet3,
            l10n.guidanceWifiErrorBullet2,
          ],
        ),
      MedLinkErrorType.route => GuidanceContent(
          title: l10n.guidanceRouteErrorTitle,
          bullets: [
            l10n.guidanceRouteErrorBullet1,
            l10n.guidanceRouteErrorBullet2,
            l10n.guidanceRouteErrorBullet3,
            l10n.guidanceRouteErrorBullet4,
          ],
        ),
      MedLinkErrorType.rdp => GuidanceContent(
          title: l10n.guidanceRdpErrorTitle,
          bullets: [
            l10n.guidanceRdpErrorBullet1,
            l10n.guidanceRdpErrorBullet2,
            l10n.guidanceRdpErrorBullet3,
          ],
        ),
      MedLinkErrorType.network ||
      MedLinkErrorType.validation ||
      MedLinkErrorType.unknown =>
        GuidanceContent(
          title: l10n.guidanceGenericErrorTitle,
          bullets: [
            l10n.guidanceGenericErrorBullet1,
            l10n.guidanceGenericErrorBullet2,
            l10n.guidanceGenericErrorBullet3,
          ],
        ),
    };
  }
}
