import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:medlink_connect/core/rdp_connection_profile.dart';
import 'package:medlink_connect/core/rdp_launch_result.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

/// Default [RdpLauncher] implementation.
///
/// Builds a standards-compliant `rdp://` URI and delegates to the
/// Microsoft Remote Desktop client via [url_launcher]. Before launching,
/// it invokes the platform channel so native code can perform last-mile
/// network preparation (split-tunnel route verification, DNS flush, etc.).
///
/// ## URI parameters sent
/// - `full address=s:{address}:{port}`      — target server
/// - `username=s:{username}`                — optional pre-filled user
/// - `audiomode=i:2`                        — bring to this computer
/// - `redirectclipboard=i:1`                — clipboard sharing
/// - `autoreconnection enabled=i:1`         — auto-reconnect on micro-cuts
/// - `connection type=i:6`                  — LAN speed profile
class DefaultRdpLauncher implements RdpLauncher {
  static const _channel = MethodChannel('com.medlinkconnect/rdp_launcher');

  /// Profiles held in memory. Consumers are responsible for persistence
  /// via [RdpConnectionProfile.toJson] / [RdpConnectionProfile.listToJson].
  final List<RdpConnectionProfile> _profiles = [];

  /// Returns an unmodifiable view of currently loaded profiles.
  List<RdpConnectionProfile> get profiles => List.unmodifiable(_profiles);

  // ------------------------------------------------------------------
  // Profile management
  // ------------------------------------------------------------------

  /// Replace the in-memory profile list with [newProfiles].
  void loadProfiles(List<RdpConnectionProfile> newProfiles) {
    _profiles
      ..clear()
      ..addAll(newProfiles);
  }

  /// Add or update a profile (matched by [RdpConnectionProfile.name]).
  void saveProfile(RdpConnectionProfile profile) {
    final idx = _profiles.indexWhere((p) => p.name == profile.name);
    if (idx >= 0) {
      _profiles[idx] = profile;
    } else {
      _profiles.add(profile);
    }
  }

  /// Remove the profile with the given [name]. Returns `true` if one
  /// was removed.
  bool removeProfile(String name) {
    final countBefore = _profiles.length;
    _profiles.removeWhere((p) => p.name == name);
    return _profiles.length < countBefore;
  }

  /// Find a profile by name.
  RdpConnectionProfile? findProfile(String name) {
    final idx = _profiles.indexWhere((p) => p.name == name);
    return idx >= 0 ? _profiles[idx] : null;
  }

  // ------------------------------------------------------------------
  // RdpLauncher interface
  // ------------------------------------------------------------------

  @override
  Future<RdpLaunchResult> launchRdp({
    String? address,
    int port = 3389,
    String? username,
    RdpConnectionProfile? profile,
  }) async {
    // Resolve the effective connection target.
    final effective = _resolveProfile(
      address: address,
      port: port,
      username: username,
      profile: profile,
    );

    // Validate.
    final validationError = effective.validate();
    if (validationError != null) {
      return RdpLaunchResult.invalidConfiguration(validationError);
    }

    // Pre-launch platform hook.
    try {
      final preResult = await _channel.invokeMethod<bool>('preLaunch', {
        'address': effective.address,
        'port': effective.port,
        'username': effective.username,
      });
      if (preResult == false) {
        return RdpLaunchResult.preLaunchDenied(
          'La plataforma rechazó el lanzamiento de RDP.',
        );
      }
    } on MissingPluginException {
      // No native implementation — proceed.
    } on PlatformException catch (e) {
      return RdpLaunchResult.preLaunchDenied(e.message);
    }

    // Check that an RDP client is reachable.
    final clientAvailable = await isRdpClientAvailable();
    if (!clientAvailable) {
      return RdpLaunchResult.clientNotFound();
    }

    // Build and launch the URI.
    final uri = _buildRdpUri(effective);

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) {
        return RdpLaunchResult.connected();
      }
      return RdpLaunchResult.launchFailed(
        'No se pudo abrir el cliente RDP.',
      );
    } catch (e) {
      return RdpLaunchResult.launchFailed(e.toString());
    }
  }

  @override
  Future<bool> isRdpClientAvailable() async {
    // Try the platform channel first.
    try {
      final result = await _channel.invokeMethod<bool>('isRdpClientAvailable');
      if (result != null) return result;
    } on MissingPluginException {
      // Fall through to url_launcher probe.
    }

    // Lightweight probe: can the OS resolve the rdp:// scheme?
    final uri = Uri.parse('rdp://check');
    return canLaunchUrl(uri);
  }

  @override
  Future<void> notifyPreLaunch(RdpConnectionProfile profile) async {
    try {
      await _channel.invokeMethod('notifyPreLaunch', {
        'address': profile.address,
        'port': profile.port,
        'username': profile.username,
      });
    } on MissingPluginException {
      // No native implementation — no-op.
    }
  }

  // ------------------------------------------------------------------
  // URI construction
  // ------------------------------------------------------------------

  /// Build a fully parameterised `rdp://` URI from [profile].
  ///
  /// Visible for testing.
  @visibleForTesting
  Uri buildRdpUriForTest(RdpConnectionProfile profile) {
    return _buildRdpUri(profile);
  }

  Uri _buildRdpUri(RdpConnectionProfile profile) {
    // Build raw query parts. The Uri() constructor handles percent-encoding
    // of the overall query string, so we must NOT pre-encode the values
    // (otherwise colons in IPv6 addresses become %3A).
    final queryParts = <String>[
      'full%20address=s:${profile.address}:${profile.port}',
      if (profile.username != null && profile.username!.isNotEmpty)
        'username=s:${profile.username!}',
      'audiomode=i:2',
      'redirectclipboard=i:1',
      'autoreconnection%20enabled=i:1',
      'connection%20type=i:6',
    ];

    // Use the Uri constructor to avoid Uri.parse's authority-parsing
    // issues with non-standard schemes like rdp://.
    // An empty host preserves the "//" in the rendered URI while
    // keeping all parameters safely in the query string.
    return Uri(
      scheme: 'rdp',
      host: '',
      query: queryParts.join('&'),
    );
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  /// Merge the optional parameters into a single [RdpConnectionProfile].
  RdpConnectionProfile _resolveProfile({
    String? address,
    int port = 3389,
    String? username,
    RdpConnectionProfile? profile,
  }) {
    if (profile != null) {
      // profile takes precedence; overlay any explicit overrides
      return profile.copyWith(
        address: address ?? profile.address,
        port: address == null ? profile.port : port,
        username: username ?? profile.username,
      );
    }
    return RdpConnectionProfile(
      name: 'Conexión directa',
      address: address ?? '',
      port: port,
      username: username,
    );
  }
}
