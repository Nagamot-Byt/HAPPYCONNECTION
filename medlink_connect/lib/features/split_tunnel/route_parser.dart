import 'package:medlink_connect/core/route_entry.dart';

/// Cross-platform parser for system routing-table output.
///
/// Supports three formats:
/// - **Windows** `route print` IPv4 table
/// - **macOS** `netstat -rn`
/// - **Linux** `ip route show`
///
/// All methods gracefully handle malformed input — they never throw.
class RouteParser {
  RouteParser._();

  /// Parse raw route-table output into a list of [RouteEntry] objects.
  ///
  /// [output] is the raw stdout from the platform-specific route command.
  /// [platform] selects the parser variant.
  ///
  /// Returns an empty list for empty or unparseable output.
  static List<RouteEntry> parseRouteOutput(
    String output,
    PlatformType platform,
  ) {
    if (output.trim().isEmpty) return [];

    try {
      switch (platform) {
        case PlatformType.windows:
          return _parseWindows(output);
        case PlatformType.macOS:
          return _parseMacOS(output);
        case PlatformType.linux:
          return _parseLinux(output);
      }
    } catch (_) {
      return [];
    }
  }

  /// Check whether [routes] contains an entry matching [cidr].
  ///
  /// Performs an exact string match on [RouteEntry.destinationCidr].
  static bool containsRoute(List<RouteEntry> routes, String cidr) {
    return routes.any((r) => r.destinationCidr == cidr);
  }

  // ────────────────────────────────────────────────────────────
  // Windows `route print` IPv4 parser
  // ────────────────────────────────────────────────────────────

  /// Parse the IPv4 section of Windows `route print` output.
  ///
  /// Expected format (headers + dashed line + rows):
  /// ```
  /// IPv4 Route Table
  /// ===========================================================================
  /// Active Routes:
  /// Network Destination        Netmask          Gateway       Interface  Metric
  ///           0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.100     25
  ///          10.0.0.0        255.0.0.0         On-link         10.0.0.50    271
  /// ```
  static List<RouteEntry> _parseWindows(String output) {
    final routes = <RouteEntry>[];
    final lines = output.split('\n');

    bool inIpv4Section = false;

    for (final line in lines) {
      final trimmed = line.trim();

      // Detect IPv4 table header
      if (trimmed.startsWith('IPv4 Route Table') ||
          trimmed.startsWith('IPv4 Route Table')) {
        inIpv4Section = true;
        continue;
      }

      if (!inIpv4Section) continue;

      // Skip section separators, headers, and blank lines
      if (trimmed.isEmpty ||
          trimmed.startsWith('==') ||
          trimmed.startsWith('Active Routes:') ||
          trimmed.startsWith('Network Destination') ||
          trimmed.startsWith('Persistent Routes:') ||
          trimmed.startsWith('IPv6') ||
          trimmed.startsWith('---')) {
        if (trimmed.startsWith('Persistent Routes:') ||
            trimmed.startsWith('IPv6')) {
          inIpv4Section = false;
        }
        continue;
      }

      final entry = _parseWindowsLine(trimmed);
      if (entry != null) {
        routes.add(entry);
      }
    }

    return routes;
  }

  /// Parse a single Windows route table row.
  ///
  /// Format: `<network>  <mask>  <gateway>  <interface>  <metric>`
  /// Returns null for lines that don't match.
  static RouteEntry? _parseWindowsLine(String line) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 4) return null;

    final network = parts[0];
    final netmask = parts[1];
    final gateway = parts[2];
    final iface = parts.length > 3 ? parts[3] : '';

    // Basic validation — each part should look like an IP or "On-link"
    if (!_looksLikeIp(network)) return null;

    final cidr = _maskToCidr(netmask);
    if (cidr == null) return null;

    return RouteEntry(
      destinationCidr: '$network/$cidr',
      gateway: gateway,
      interfaceName: iface,
    );
  }

  // ────────────────────────────────────────────────────────────
  // macOS `netstat -rn` parser
  // ────────────────────────────────────────────────────────────

  /// Parse macOS `netstat -rn` output.
  ///
  /// Expected format (header, then rows):
  /// ```
  /// Routing tables
  ///
  /// Internet:
  /// Destination        Gateway            Flags        Netif Expire
  /// default            192.168.1.1        UGSc           en0
  /// 10.0.0.0/8         link#13            UCS          utun4
  /// 192.168.1.0/24     link#6             UCS            en0       !
  /// ```
  static List<RouteEntry> _parseMacOS(String output) {
    final routes = <RouteEntry>[];
    final lines = output.split('\n');

    bool inInternetSection = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.startsWith('Internet:')) {
        inInternetSection = true;
        continue;
      }

      if (!inInternetSection) continue;

      // Skip headers and blank lines
      if (trimmed.isEmpty ||
          trimmed.startsWith('Destination') ||
          trimmed.startsWith('Routing tables')) {
        continue;
      }

      // Exit internet section on next section header
      if (trimmed.startsWith('Internet6:') || trimmed.startsWith('Ethernet:')) {
        inInternetSection = false;
        continue;
      }

      final entry = _parseMacOSLine(trimmed);
      if (entry != null) {
        routes.add(entry);
      }
    }

    return routes;
  }

  /// Parse a single macOS `netstat -rn` row.
  static RouteEntry? _parseMacOSLine(String line) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 3) return null;

    var destination = parts[0];
    final gateway = parts[1];
    final iface = parts.length > 3 ? parts[3] : '';

    // "default" route → 0.0.0.0/0
    if (destination == 'default') {
      destination = '0.0.0.0/0';
    }

    // If destination already has CIDR, use it; otherwise try to infer
    if (!destination.contains('/')) {
      // Without netmask info in netstat, assume /32 for hosts, skip for now
      // We only reliably capture entries that include CIDR notation
      destination = '$destination/32';
    }

    return RouteEntry(
      destinationCidr: destination,
      gateway: gateway,
      interfaceName: iface,
    );
  }

  // ────────────────────────────────────────────────────────────
  // Linux `ip route show` parser
  // ────────────────────────────────────────────────────────────

  /// Parse Linux `ip route show` output.
  ///
  /// Expected format:
  /// ```
  /// default via 192.168.1.1 dev eth0
  /// 10.0.0.0/8 via 10.0.0.1 dev tun0
  /// 192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.100
  /// ```
  static List<RouteEntry> _parseLinux(String output) {
    final routes = <RouteEntry>[];
    final lines = output.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final entry = _parseLinuxLine(trimmed);
      if (entry != null) {
        routes.add(entry);
      }
    }

    return routes;
  }

  /// Parse a single Linux `ip route show` row.
  static RouteEntry? _parseLinuxLine(String line) {
    final tokens = line.split(RegExp(r'\s+'));
    if (tokens.isEmpty) return null;

    String? cidr;
    String? gateway;
    String? iface;

    // First token is either "default" or a CIDR
    if (tokens[0] == 'default') {
      cidr = '0.0.0.0/0';
    } else if (tokens[0].contains('/')) {
      cidr = tokens[0];
    } else {
      // Unrecognised format
      return null;
    }

    for (var i = 1; i < tokens.length; i++) {
      if (tokens[i] == 'via' && i + 1 < tokens.length) {
        gateway = tokens[i + 1];
        i++;
      } else if (tokens[i] == 'dev' && i + 1 < tokens.length) {
        iface = tokens[i + 1];
        i++;
      }
    }

    if (cidr == null) return null;

    return RouteEntry(
      destinationCidr: cidr,
      gateway: gateway ?? '',
      interfaceName: iface ?? '',
    );
  }

  // ────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────

  /// Very loose IP-address shape check.
  static bool _looksLikeIp(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  /// Convert a dotted-decimal subnet mask to a CIDR prefix length.
  ///
  /// Example: `"255.255.255.0"` → `24`.
  /// Returns null for invalid masks.
  static int? _maskToCidr(String mask) {
    if (!_looksLikeIp(mask)) return null;
    final parts = mask.split('.').map(int.parse).toList();

    var prefix = 0;
    for (final octet in parts) {
      // Count leading 1 bits in the octet
      var bits = octet;
      for (var i = 7; i >= 0; i--) {
        if ((bits & (1 << i)) != 0) {
          prefix++;
        } else {
          // All remaining bits must be zero for a valid subnet mask
          final remaining = bits & ((1 << i) - 1);
          if (remaining != 0) return null;
          // Check remaining octets are zero
          final octetIndex = parts.indexOf(octet);
          for (var j = octetIndex + 1; j < parts.length; j++) {
            if (parts[j] != 0) return null;
          }
          return prefix;
        }
      }
    }
    return prefix;
  }
}
