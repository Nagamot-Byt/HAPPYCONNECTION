import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/route_entry.dart';
import 'package:medlink_connect/features/split_tunnel/route_parser.dart';

void main() {
  group('RouteParser.parseRouteOutput', () {
    // ──────────────────────────────────────────────────────
    // Windows
    // ──────────────────────────────────────────────────────

    group('Windows route print', () {
      test('parses standard IPv4 route table', () {
        const output = '''
===========================================================================
Interface List
 12...00 15 5d 01 4a 0c ......Hyper-V Virtual Ethernet Adapter
 6...00 1a 2b 3c 4d 5e ......Intel(R) Ethernet Connection

===========================================================================

IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.100     25
         10.0.0.0        255.0.0.0         On-link         10.0.0.50    271
      127.0.0.0        255.0.0.0         On-link         127.0.0.1    331
      127.0.0.1  255.255.255.255         On-link         127.0.0.1    331
  127.255.255.255  255.255.255.255         On-link         127.0.0.1    331
     192.168.1.0    255.255.255.0         On-link      192.168.1.100    281
   192.168.1.100  255.255.255.255         On-link      192.168.1.100    281
   192.168.1.255  255.255.255.255         On-link      192.168.1.100    281
        224.0.0.0        240.0.0.0         On-link         127.0.0.1    331
  255.255.255.255  255.255.255.255         On-link         127.0.0.1    331
===========================================================================
Persistent Routes:
  None
''';

        final routes = RouteParser.parseRouteOutput(
          output,
          PlatformType.windows,
        );

        expect(routes.length, greaterThanOrEqualTo(5));

        // Verify the 10.0.0.0/8 route
        final hospitalRoute = routes.firstWhere(
          (r) => r.destinationCidr == '10.0.0.0/8',
          orElse: () => throw 'Route not found',
        );
        expect(hospitalRoute.gateway, 'On-link');
        expect(hospitalRoute.interfaceName, '10.0.0.50');
      });

      test('skips IPv6 section', () {
        const output = '''
IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.100     25
===========================================================================
Persistent Routes:
  None

IPv6 Route Table
===========================================================================
Active Routes:
 If Metric Network Destination      Gateway
  1    331 ::1/128                  On-link
===========================================================================
''';

        final routes = RouteParser.parseRouteOutput(
          output,
          PlatformType.windows,
        );

        expect(routes.length, 1);
        expect(routes[0].destinationCidr, '0.0.0.0/0');
      });
    });

    // ──────────────────────────────────────────────────────
    // macOS
    // ──────────────────────────────────────────────────────

    group('macOS netstat -rn', () {
      test('parses standard internet routes', () {
        const output = '''
Routing tables

Internet:
Destination        Gateway            Flags        Netif Expire
default            192.168.1.1        UGSc           en0
10.0.0.0/8         link#13            UCS          utun4
127.0.0.1          127.0.0.1          UH             lo0
169.254.0.0/16      link#6             UCS            en0       !
192.168.1.0/24      link#6             UCS            en0       !
192.168.1.100/32    link#6             UCS            en0       !

Internet6:
Destination                             Gateway                         Flags         Netif Expire
::1                                     ::1                             UHL            lo0
''';

        final routes = RouteParser.parseRouteOutput(
          output,
          PlatformType.macOS,
        );

        expect(routes.length, greaterThanOrEqualTo(4));

        // Default route
        final defaultRoute = routes.firstWhere(
          (r) => r.destinationCidr == '0.0.0.0/0',
          orElse: () => throw 'Default route not found',
        );
        expect(defaultRoute.gateway, '192.168.1.1');

        // Hospital subnet
        final hospitalRoute = routes.firstWhere(
          (r) => r.destinationCidr == '10.0.0.0/8',
          orElse: () => throw 'Hospital route not found',
        );
        expect(hospitalRoute.interfaceName, 'utun4');
      });

      test('stops parsing at Internet6 section', () {
        const output = '''
Internet:
Destination        Gateway            Flags        Netif Expire
10.0.0.0/8         link#13            UCS          utun4

Internet6:
Destination                             Gateway                         Flags         Netif Expire
fe80::%utun4                            link#13                         UCSI         utun4
''';

        final routes = RouteParser.parseRouteOutput(
          output,
          PlatformType.macOS,
        );

        expect(routes.length, 1);
        expect(routes[0].destinationCidr, '10.0.0.0/8');
      });
    });

    // ──────────────────────────────────────────────────────
    // Linux
    // ──────────────────────────────────────────────────────

    group('Linux ip route show', () {
      test('parses standard routes', () {
        const output = '''
default via 192.168.1.1 dev eth0
10.0.0.0/8 via 10.0.0.1 dev tun0
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1 linkdown
192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.100
''';

        final routes = RouteParser.parseRouteOutput(
          output,
          PlatformType.linux,
        );

        expect(routes.length, 4);

        // Default
        expect(routes[0].destinationCidr, '0.0.0.0/0');
        expect(routes[0].gateway, '192.168.1.1');
        expect(routes[0].interfaceName, 'eth0');

        // Hospital
        expect(routes[1].destinationCidr, '10.0.0.0/8');
        expect(routes[1].gateway, '10.0.0.1');
        expect(routes[1].interfaceName, 'tun0');
      });

      test('handles routes without via', () {
        const output = '192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.100';

        final routes = RouteParser.parseRouteOutput(
          output,
          PlatformType.linux,
        );

        expect(routes.length, 1);
        expect(routes[0].destinationCidr, '192.168.1.0/24');
        expect(routes[0].gateway, '');
        expect(routes[0].interfaceName, 'eth0');
      });
    });

    // ──────────────────────────────────────────────────────
    // Edge cases
    // ──────────────────────────────────────────────────────

    group('edge cases', () {
      test('returns empty list for empty output', () {
        expect(
          RouteParser.parseRouteOutput('', PlatformType.windows),
          isEmpty,
        );
        expect(
          RouteParser.parseRouteOutput('', PlatformType.macOS),
          isEmpty,
        );
        expect(
          RouteParser.parseRouteOutput('', PlatformType.linux),
          isEmpty,
        );
      });

      test('returns empty list for whitespace-only output', () {
        expect(
          RouteParser.parseRouteOutput('   \n  \n  ', PlatformType.linux),
          isEmpty,
        );
      });

      test('returns empty list for malformed output', () {
        const output = 'This is not a routing table\nJust random text\n';

        final routes = RouteParser.parseRouteOutput(
          output,
          PlatformType.windows,
        );
        expect(routes, isEmpty);
      });

      test('returns empty list for Windows output with no IPv4 section', () {
        const output = '''
IPv6 Route Table
===========================================================================
Active Routes:
  1    331 ::1/128                  On-link
''';

        final routes = RouteParser.parseRouteOutput(
          output,
          PlatformType.windows,
        );
        expect(routes, isEmpty);
      });

      test('parsers never throw — unknown platform caught gracefully', () {
        // All platforms should handle gracefully; we test the try/catch path
        // by confirming even weird input never throws.
        const weirdOutput = '\x00\x01\x02'; // Binary garbage

        expect(
          () => RouteParser.parseRouteOutput(weirdOutput, PlatformType.windows),
          returnsNormally,
        );
        expect(
          () => RouteParser.parseRouteOutput(weirdOutput, PlatformType.macOS),
          returnsNormally,
        );
        expect(
          () => RouteParser.parseRouteOutput(weirdOutput, PlatformType.linux),
          returnsNormally,
        );
      });
    });

    // ──────────────────────────────────────────────────────
    // containsRoute
    // ──────────────────────────────────────────────────────

    group('containsRoute', () {
      test('returns true when route is present', () {
        const output = '10.0.0.0/8 via 10.0.0.1 dev tun0';
        final routes = RouteParser.parseRouteOutput(output, PlatformType.linux);
        expect(RouteParser.containsRoute(routes, '10.0.0.0/8'), isTrue);
      });

      test('returns false when route is absent', () {
        const output = '192.168.1.0/24 dev eth0';
        final routes = RouteParser.parseRouteOutput(output, PlatformType.linux);
        expect(RouteParser.containsRoute(routes, '10.0.0.0/8'), isFalse);
      });

      test('returns false for empty list', () {
        expect(RouteParser.containsRoute([], '10.0.0.0/8'), isFalse);
      });
    });
  });
}
