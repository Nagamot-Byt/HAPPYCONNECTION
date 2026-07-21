import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/features/health_check/ping_parser.dart';

void main() {
  group('PingParser.parseLatency', () {
    group('Windows output', () {
      test('parses English "Average = XXms"', () {
        const output = '''
Pinging 8.8.8.8 with 32 bytes of data:
Reply from 8.8.8.8: bytes=32 time=12ms TTL=118
Reply from 8.8.8.8: bytes=32 time=14ms TTL=118
Reply from 8.8.8.8: bytes=32 time=11ms TTL=118
Reply from 8.8.8.8: bytes=32 time=15ms TTL=118

Ping statistics for 8.8.8.8:
    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss),
Approximate round trip times in milli-seconds:
    Minimum = 11ms, Maximum = 15ms, Average = 13ms
''';
        expect(PingParser.parseLatency(output, isWindows: true), 13);
      });

      test('parses Spanish "Media = XXms"', () {
        const output = '''
Haciendo ping a 8.8.8.8 con 32 bytes de datos:
Respuesta desde 8.8.8.8: bytes=32 tiempo=12ms TTL=118
Respuesta desde 8.8.8.8: bytes=32 tiempo=14ms TTL=118
Respuesta desde 8.8.8.8: bytes=32 tiempo=11ms TTL=118
Respuesta desde 8.8.8.8: bytes=32 tiempo=15ms TTL=118

Estadísticas de ping para 8.8.8.8:
    Paquetes: enviados = 4, recibidos = 4, perdidos = 0
    (0% pérdidos),
Tiempos aproximados de ida y vuelta en milisegundos:
    Mínimo = 11ms, Máximo = 15ms, Media = 13ms
''';
        expect(PingParser.parseLatency(output, isWindows: true), 13);
      });

      test('returns null for unreachable host', () {
        const output = '''
Pinging 10.255.255.1 with 32 bytes of data:
Request timed out.
Request timed out.
Request timed out.
Request timed out.

Ping statistics for 10.255.255.1:
    Packets: Sent = 4, Received = 0, Lost = 4 (100% loss),
''';
        expect(PingParser.parseLatency(output, isWindows: true), isNull);
      });

      test('returns null for empty output', () {
        expect(PingParser.parseLatency('', isWindows: true), isNull);
      });
    });

    group('Unix output (macOS/Linux)', () {
      test('parses standard min/avg/max/stddev format', () {
        const output = '''
PING 8.8.8.8 (8.8.8.8): 56 data bytes
64 bytes from 8.8.8.8: icmp_seq=0 ttl=118 time=12.345 ms
64 bytes from 8.8.8.8: icmp_seq=1 ttl=118 time=14.567 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=118 time=11.234 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=118 time=15.890 ms

--- 8.8.8.8 ping statistics ---
4 packets transmitted, 4 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 11.234/13.509/15.890/1.756 ms
''';
        final result = PingParser.parseLatency(output, isWindows: false);
        expect(result, isNotNull);
        // avg = 13.509 → rounds to 14
        expect(result, 14);
      });

      test('parses "rtt min/avg/max/mdev" variant', () {
        const output = '''
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=118 time=10.0 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=118 time=10.0 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=118 time=10.0 ms
64 bytes from 8.8.8.8: icmp_seq=4 ttl=118 time=10.0 ms

--- 8.8.8.8 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3004ms
rtt min/avg/max/mdev = 10.000/10.000/10.000/0.000 ms
''';
        final result = PingParser.parseLatency(output, isWindows: false);
        expect(result, 10);
      });

      test('returns null for 100% packet loss', () {
        const output = '''
PING 10.255.255.1 (10.255.255.1): 56 data bytes

--- 10.255.255.1 ping statistics ---
4 packets transmitted, 0 packets received, 100.0% packet loss
''';
        expect(PingParser.parseLatency(output, isWindows: false), isNull);
      });

      test('returns null for empty output', () {
        expect(PingParser.parseLatency('', isWindows: false), isNull);
      });
    });
  });

  group('PingParser.parseStatsMap', () {
    test('parses int avg', () {
      expect(PingParser.parseStatsMap({'avg': 42}), 42);
    });

    test('parses double avg', () {
      expect(PingParser.parseStatsMap({'avg': 42.7}), 43);
    });

    test('parses string avg', () {
      expect(PingParser.parseStatsMap({'avg': '42'}), 42);
    });

    test('returns null for null map', () {
      expect(PingParser.parseStatsMap(null), isNull);
    });

    test('returns null for missing avg key', () {
      expect(PingParser.parseStatsMap({'min': 10, 'max': 100}), isNull);
    });
  });
}
