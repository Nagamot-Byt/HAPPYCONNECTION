import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/input_sanitizer.dart';

void main() {
  group('InputSanitizer - sanitizeIpv4', () {
    test('accepts valid IPv4 addresses', () {
      expect(InputSanitizer.sanitizeIpv4('192.168.1.1'), '192.168.1.1');
      expect(InputSanitizer.sanitizeIpv4('  10.0.0.1  '), '10.0.0.1');
      expect(InputSanitizer.sanitizeIpv4('172.16.254.1'), '172.16.254.1');
    });

    test('rejects empty or whitespace input', () {
      expect(() => InputSanitizer.sanitizeIpv4(''), throwsArgumentError);
      expect(() => InputSanitizer.sanitizeIpv4('   '), throwsArgumentError);
    });

    test('rejects shell metacharacters', () {
      expect(() => InputSanitizer.sanitizeIpv4('192.168.1.1; rm -rf /'),
          throwsArgumentError);
      expect(() => InputSanitizer.sanitizeIpv4('10.0.0.1 | dir'),
          throwsArgumentError);
      expect(() => InputSanitizer.sanitizeIpv4('10.0.0.1 && notepad'),
          throwsArgumentError);
      expect(() => InputSanitizer.sanitizeIpv4('`calc`'), throwsArgumentError);
      expect(
          () => InputSanitizer.sanitizeIpv4('\$(whoami)'), throwsArgumentError);
    });

    test('rejects malformed IP formats', () {
      expect(
          () => InputSanitizer.sanitizeIpv4('256.0.0.1'), throwsArgumentError);
      expect(
          () => InputSanitizer.sanitizeIpv4('192.168.1'), throwsArgumentError);
      expect(() => InputSanitizer.sanitizeIpv4('abc.def.ghi.jkl'),
          throwsArgumentError);
    });
  });

  group('InputSanitizer - sanitizeCidr', () {
    test('accepts valid CIDR notation', () {
      expect(InputSanitizer.sanitizeCidr('10.0.0.0/8'), '10.0.0.0/8');
      expect(InputSanitizer.sanitizeCidr('172.16.0.0/12'), '172.16.0.0/12');
      expect(InputSanitizer.sanitizeCidr('192.168.0.0/16'), '192.168.0.0/16');
      expect(InputSanitizer.sanitizeCidr('192.168.1.1/32'), '192.168.1.1/32');
    });

    test('accepts plain IP without mask', () {
      expect(InputSanitizer.sanitizeCidr('192.168.1.1'), '192.168.1.1');
    });

    test('rejects out of range prefix', () {
      expect(() => InputSanitizer.sanitizeCidr('10.0.0.0/33'),
          throwsArgumentError);
      expect(() => InputSanitizer.sanitizeCidr('10.0.0.0/-1'),
          throwsArgumentError);
    });

    test('rejects injection in CIDR', () {
      expect(() => InputSanitizer.sanitizeCidr('10.0.0.0/8; echo hack'),
          throwsArgumentError);
    });
  });

  group('InputSanitizer - sanitizeHostname', () {
    test('accepts valid hostnames and IPs', () {
      expect(InputSanitizer.sanitizeHostname('serv_pediatrico.huv.gov.co'),
          'serv_pediatrico.huv.gov.co');
      expect(InputSanitizer.sanitizeHostname('192.168.1.100'), '192.168.1.100');
      expect(InputSanitizer.sanitizeHostname('rdp-server-01'), 'rdp-server-01');
    });

    test('rejects hostnames with shell metacharacters', () {
      expect(() => InputSanitizer.sanitizeHostname('server.com; calc'),
          throwsArgumentError);
      expect(() => InputSanitizer.sanitizeHostname('`whoami`.domain.com'),
          throwsArgumentError);
    });
  });

  group('InputSanitizer - sanitizePort', () {
    test('accepts valid port numbers', () {
      expect(InputSanitizer.sanitizePort('3389'), 3389);
      expect(InputSanitizer.sanitizePort('80'), 80);
      expect(InputSanitizer.sanitizePort('65535'), 65535);
    });

    test('rejects invalid or out of bounds ports', () {
      expect(() => InputSanitizer.sanitizePort('0'), throwsArgumentError);
      expect(() => InputSanitizer.sanitizePort('65536'), throwsArgumentError);
      expect(() => InputSanitizer.sanitizePort('abc'), throwsArgumentError);
      expect(
          () => InputSanitizer.sanitizePort('3389; dir'), throwsArgumentError);
    });
  });

  group('InputSanitizer - interface and Wi-Fi names', () {
    test('accepts real Windows and Linux interface names', () {
      expect(InputSanitizer.sanitizeInterfaceName('Wi-Fi'), 'Wi-Fi');
      expect(InputSanitizer.sanitizeInterfaceName('vEthernet (Default Switch)'),
          'vEthernet (Default Switch)');
      expect(InputSanitizer.sanitizeInterfaceName('enp3s0.100'), 'enp3s0.100');
      expect(InputSanitizer.sanitizeInterfaceName('Wi-Fi 2.4 GHz'),
          'Wi-Fi 2.4 GHz');
    });

    test('rejects control characters and empty interface names', () {
      expect(() => InputSanitizer.sanitizeInterfaceName('Wi-Fi\nGuest'),
          throwsArgumentError);
      expect(() => InputSanitizer.sanitizeInterfaceName('   '),
          throwsArgumentError);
    });

    test('enforces the stricter Android interface charset', () {
      expect(InputSanitizer.sanitizeInterfaceName('wlan0', android: true),
          'wlan0');
      expect(
          () => InputSanitizer.sanitizeInterfaceName('Wi-Fi 2.4 GHz',
              android: true),
          throwsArgumentError);
      expect(
          () => InputSanitizer.sanitizeInterfaceName(
              'vEthernet (Default Switch)',
              android: true),
          throwsArgumentError);
    });

    test('accepts SSIDs with punctuation and accents', () {
      expect(InputSanitizer.sanitizeSsid('HUV & Visitantes (5G)'),
          'HUV & Visitantes (5G)');
      expect(InputSanitizer.sanitizeSsid('Wi-Fi Pediatría'), 'Wi-Fi Pediatría');
    });

    test('rejects control characters and long SSIDs', () {
      expect(() => InputSanitizer.sanitizeSsid('HUV\r\nGuest'),
          throwsArgumentError);
      expect(() => InputSanitizer.sanitizeSsid('x' * 33), throwsArgumentError);
    });
  });

  group('InputSanitizer - sanitizeRdpCredential', () {
    test('accepts domain credentials', () {
      expect(
          InputSanitizer.sanitizeRdpCredential('HUV\\doctor'), 'HUV\\doctor');
      expect(InputSanitizer.sanitizeRdpCredential(' doctor '), 'doctor');
    });

    test('rejects newlines and empty credentials', () {
      expect(
          () => InputSanitizer.sanitizeRdpCredential(
              'doctor\r\nfull address:s:evil'),
          throwsArgumentError);
      expect(
          () => InputSanitizer.sanitizeRdpCredential(' '), throwsArgumentError);
    });
  });

  group('InputSanitizer - sanitizeSubnets', () {
    test('sanitizes list of subnets', () {
      final list = ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'];
      expect(InputSanitizer.sanitizeSubnets(list), list);
    });

    test('rejects empty list', () {
      expect(() => InputSanitizer.sanitizeSubnets([]), throwsArgumentError);
    });
  });
}
