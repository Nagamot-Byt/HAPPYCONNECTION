import 'package:flutter/services.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

/// Default [RdpLauncher] that first tries a platform channel (for any
/// platform-specific pre-launch logic) and then falls back to
/// [url_launcher] for the `rdp://` / `ms-rd-web://` URI scheme.
class DefaultRdpLauncher implements RdpLauncher {
  static const _channel = MethodChannel('com.medlinkconnect/rdp_launcher');

  @override
  Future<bool> launchRdp({
    String? address,
    int port = 3389,
    String? username,
    String? fullAddress,
  }) async {
    // Allow platform-specific pre-launch hook.
    try {
      final preResult = await _channel.invokeMethod<bool>('preLaunch', {
        'address': address,
        'port': port,
        'username': username,
        'fullAddress': fullAddress,
      });
      if (preResult == false) return false;
    } on MissingPluginException {
      // No platform implementation — proceed with url_launcher.
    }

    // Build the RDP URI.
    final uriStr = fullAddress ??
        'rdp://full%20address=s:${address ?? ''}:$port'
            '${username != null ? '&username=s:$username' : ''}';

    final uri = Uri.parse(uriStr);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    return false;
  }

  @override
  Future<bool> isRdpClientAvailable() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isRdpClientAvailable');
      if (result != null) return result;
    } on MissingPluginException {
      // Fall through.
    }

    // Check if the rdp:// scheme can be launched.
    final uri = Uri.parse('rdp://check');
    return canLaunchUrl(uri);
  }
}
