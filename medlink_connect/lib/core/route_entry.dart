/// Represents a single entry in the system routing table.
///
/// Each [RouteEntry] models a route that directs traffic matching
/// [destinationCidr] to a specific [gateway] on [interfaceName].
class RouteEntry {
  /// Destination network in CIDR notation (e.g. "10.0.0.0/8").
  final String destinationCidr;

  /// Gateway IP address for this route.
  final String gateway;

  /// Network interface name (e.g. "eth0", "Wi-Fi").
  final String interfaceName;

  /// Whether this route should persist across reboots.
  final bool isPersistent;

  const RouteEntry({
    required this.destinationCidr,
    required this.gateway,
    required this.interfaceName,
    this.isPersistent = false,
  });

  /// Extract the subnet mask from a CIDR notation string.
  ///
  /// Example:
  /// ```dart
  /// RouteEntry.fromCidr('10.0.0.0/8'); // → '255.0.0.0'
  /// RouteEntry.fromCidr('192.168.1.0/24'); // → '255.255.255.0'
  /// ```
  ///
  /// Returns an empty string if the input is malformed or lacks a `/` prefix.
  static String fromCidr(String cidr) {
    final slashIndex = cidr.indexOf('/');
    if (slashIndex == -1 || slashIndex == cidr.length - 1) {
      return '';
    }

    final prefixLength = int.tryParse(cidr.substring(slashIndex + 1));
    if (prefixLength == null || prefixLength < 0 || prefixLength > 32) {
      return '';
    }

    return _prefixToSubnetMask(prefixLength);
  }

  /// Convert a prefix length (0–32) to dotted-decimal subnet mask.
  static String _prefixToSubnetMask(int prefixLength) {
    if (prefixLength == 0) return '0.0.0.0';

    final mask = (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF;
    return '${(mask >> 24) & 0xFF}.${(mask >> 16) & 0xFF}.${(mask >> 8) & 0xFF}.${mask & 0xFF}';
  }

  /// Build an OS-specific command string to add this route.
  ///
  /// [platform] selects the target OS format.
  ///
  /// - **Windows**: `route add <network> mask <mask> <gateway> [IF <ifIndex>] [/p]`
  /// - **macOS**: `route -n add -net <network> -netmask <mask> <gateway> -interface <ifName>`
  /// - **Linux**: `ip route add <cidr> via <gateway> dev <ifName>`
  ///
  /// Returns null if [destinationCidr] cannot be parsed.
  String? toRouteCommand(PlatformType platform) {
    final network = _networkAddress;
    final mask = fromCidr(destinationCidr);
    if (network.isEmpty || mask.isEmpty) return null;

    switch (platform) {
      case PlatformType.windows:
        final parts = [
          'route',
          'add',
          network,
          'mask',
          mask,
          gateway,
        ];
        if (interfaceName.isNotEmpty) {
          parts.add('IF');
          parts.add(interfaceName);
        }
        if (isPersistent) {
          parts.add('/p');
        }
        return parts.join(' ');

      case PlatformType.macOS:
        final parts = [
          'route',
          '-n',
          'add',
          '-net',
          network,
          '-netmask',
          mask,
          gateway,
        ];
        if (interfaceName.isNotEmpty) {
          parts.add('-interface');
          parts.add(interfaceName);
        }
        return parts.join(' ');

      case PlatformType.linux:
        final parts = [
          'ip',
          'route',
          'add',
          destinationCidr,
          'via',
          gateway,
        ];
        if (interfaceName.isNotEmpty) {
          parts.add('dev');
          parts.add(interfaceName);
        }
        return parts.join(' ');
    }
  }

  /// Extract the network address portion from [destinationCidr].
  ///
  /// Example: `"10.0.0.0/8"` → `"10.0.0.0"`.
  String get _networkAddress {
    final slashIndex = destinationCidr.indexOf('/');
    if (slashIndex == -1) return destinationCidr;
    return destinationCidr.substring(0, slashIndex);
  }

  @override
  String toString() =>
      'RouteEntry(destination: $destinationCidr, gateway: $gateway, '
      'interface: $interfaceName, persistent: $isPersistent)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteEntry &&
          destinationCidr == other.destinationCidr &&
          gateway == other.gateway &&
          interfaceName == other.interfaceName &&
          isPersistent == other.isPersistent;

  @override
  int get hashCode => Object.hash(
        destinationCidr,
        gateway,
        interfaceName,
        isPersistent,
      );
}

/// Enumeration of supported desktop platforms for route-command generation.
enum PlatformType {
  windows,
  macOS,
  linux,
}
