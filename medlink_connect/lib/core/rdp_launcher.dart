import 'package:medlink_connect/core/rdp_connection_profile.dart';
import 'package:medlink_connect/core/rdp_launch_result.dart';

/// Abstract interface for launching an RDP session via deep linking.
///
/// We never embed an RDP viewer — we always delegate to Microsoft's
/// official Remote Desktop client (or a compatible third-party client)
/// using the `rdp://` or `ms-rd-web://` URI scheme.
abstract class RdpLauncher {
  /// Launch the Microsoft Remote Desktop client (or equivalent) with the
  /// given connection parameters.
  ///
  /// Provide either [profile] (a complete [RdpConnectionProfile]) **or**
  /// the individual fields ([address], [port], [username]). If both are
  /// supplied, [profile] takes precedence.
  ///
  /// Returns an [RdpLaunchResult] with a Spanish message suitable for
  /// direct display to clinical staff.
  Future<RdpLaunchResult> launchRdp({
    String? address,
    int port = 3389,
    String? username,
    RdpConnectionProfile? profile,
  });

  /// Check whether an RDP client is installed on this device.
  ///
  /// Tries `canLaunchUrl(Uri.parse('rdp://check'))` as a lightweight
  /// probe. May also query the platform channel on supported platforms.
  Future<bool> isRdpClientAvailable();

  /// Notify the native platform that an RDP launch is about to occur.
  ///
  /// Implementations may use this to perform last-mile network prep
  /// (e.g. ensuring split-tunnel routes are active).
  Future<void> notifyPreLaunch(RdpConnectionProfile profile);
}
