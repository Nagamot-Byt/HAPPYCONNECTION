import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/rdp_connection_profile.dart';

/// Pure unit tests for [RdpConnectionProfile] — serialization, validation,
/// and edge cases.  No Flutter runtime needed.
void main() {
  group('RdpConnectionProfile JSON round-trip', () {
    test('round-trips all fields', () {
      final profile = RdpConnectionProfile(
        name: 'Servidor Ginecología',
        address: '10.0.0.100',
        port: 3389,
        username: 'dr.garcia',
      );

      final json = profile.toJson();
      final restored = RdpConnectionProfile.fromJson(json);

      expect(restored.name, 'Servidor Ginecología');
      expect(restored.address, '10.0.0.100');
      expect(restored.port, 3389);
      expect(restored.username, 'dr.garcia');
    });

    test('round-trips without optional username', () {
      final profile = RdpConnectionProfile(
        name: 'Solo Address',
        address: '192.168.1.1',
      );

      final json = profile.toJson();
      expect(json.containsKey('username'), isFalse);

      final restored = RdpConnectionProfile.fromJson(json);
      expect(restored.username, isNull);
      expect(restored.port, 3389); // default
    });

    test('fromJson defaults missing port to 3389', () {
      final restored = RdpConnectionProfile.fromJson({
        'name': 'Test',
        'address': '10.0.0.1',
      });

      expect(restored.port, 3389);
    });

    test('fromJson handles port as double (JSON quirk)', () {
      final restored = RdpConnectionProfile.fromJson({
        'name': 'Test',
        'address': '10.0.0.1',
        'port': 3390.0,
      });

      expect(restored.port, 3390);
    });

    test('fromJson handles port as int string', () {
      final restored = RdpConnectionProfile.fromJson({
        'name': 'Test',
        'address': '10.0.0.1',
        'port': 3390,
      });

      expect(restored.port, 3390);
    });

    test('fromJson handles missing name gracefully', () {
      final restored = RdpConnectionProfile.fromJson({
        'address': '10.0.0.1',
      });

      expect(restored.name, '');
    });
  });

  group('RdpConnectionProfile list serialization', () {
    test('listToJson / listFromJson round-trips', () {
      final profiles = [
        RdpConnectionProfile(name: 'A', address: '10.0.0.1'),
        RdpConnectionProfile(
            name: 'B', address: '10.0.0.2', username: 'userB'),
      ];

      final json = RdpConnectionProfile.listToJson(profiles);
      final restored = RdpConnectionProfile.listFromJson(json);

      expect(restored.length, 2);
      expect(restored[0].name, 'A');
      expect(restored[1].username, 'userB');
    });

    test('listFromJson handles empty list', () {
      final restored = RdpConnectionProfile.listFromJson('[]');
      expect(restored, isEmpty);
    });
  });

  group('RdpConnectionProfile validation', () {
    test('valid profile returns null', () {
      final profile = RdpConnectionProfile(
        name: 'OK',
        address: '10.0.0.1',
      );
      expect(profile.validate(), isNull);
      expect(profile.isValid, isTrue);
    });

    test('empty name is invalid', () {
      final profile = RdpConnectionProfile(name: '', address: '10.0.0.1');
      expect(profile.validate(), contains('nombre'));
      expect(profile.isValid, isFalse);
    });

    test('whitespace-only name is invalid', () {
      final profile = RdpConnectionProfile(name: '   ', address: '10.0.0.1');
      expect(profile.validate(), contains('nombre'));
      expect(profile.isValid, isFalse);
    });

    test('empty address is invalid', () {
      final profile = RdpConnectionProfile(name: 'Test', address: '');
      expect(profile.validate(), contains('dirección'));
      expect(profile.isValid, isFalse);
    });

    test('port 0 is invalid', () {
      final profile =
          RdpConnectionProfile(name: 'Test', address: '10.0.0.1', port: 0);
      expect(profile.validate(), contains('puerto'));
      expect(profile.isValid, isFalse);
    });

    test('port 65536 is invalid', () {
      final profile =
          RdpConnectionProfile(name: 'Test', address: '10.0.0.1', port: 65536);
      expect(profile.validate(), contains('puerto'));
      expect(profile.isValid, isFalse);
    });

    test('negative port is invalid', () {
      final profile =
          RdpConnectionProfile(name: 'Test', address: '10.0.0.1', port: -1);
      expect(profile.validate(), contains('puerto'));
      expect(profile.isValid, isFalse);
    });
  });

  group('RdpConnectionProfile copyWith', () {
    test('copies all fields', () {
      final original = RdpConnectionProfile(
        name: 'Orig',
        address: '10.0.0.1',
        port: 3390,
        username: 'user',
      );
      final copy = original.copyWith(name: 'Copy');

      expect(copy.name, 'Copy');
      expect(copy.address, '10.0.0.1');
      expect(copy.port, 3390);
      expect(copy.username, 'user');
    });

    test('clearUsername removes username', () {
      final original = RdpConnectionProfile(
        name: 'Orig',
        address: '10.0.0.1',
        username: 'user',
      );
      final copy = original.copyWith(clearUsername: true);

      expect(copy.username, isNull);
    });

    test('copyWith does not mutate original', () {
      final original = RdpConnectionProfile(
        name: 'Orig',
        address: '10.0.0.1',
      );
      // ignore: unused_local_variable
      final copy = original.copyWith(name: 'Copy');

      expect(original.name, 'Orig');
    });
  });

  group('RdpConnectionProfile equality', () {
    test('identical profiles are equal', () {
      final a = RdpConnectionProfile(name: 'X', address: '10.0.0.1');
      final b = RdpConnectionProfile(name: 'X', address: '10.0.0.1');
      expect(a, b);
    });

    test('different name makes unequal', () {
      final a = RdpConnectionProfile(name: 'A', address: '10.0.0.1');
      final b = RdpConnectionProfile(name: 'B', address: '10.0.0.1');
      expect(a, isNot(b));
    });

    test('different address makes unequal', () {
      final a = RdpConnectionProfile(name: 'X', address: '10.0.0.1');
      final b = RdpConnectionProfile(name: 'X', address: '10.0.0.2');
      expect(a, isNot(b));
    });

    test('toString contains key fields', () {
      final profile = RdpConnectionProfile(
        name: 'Test',
        address: '10.0.0.1',
        username: 'doctor',
      );
      final s = profile.toString();
      expect(s, contains('Test'));
      expect(s, contains('10.0.0.1'));
      expect(s, contains('doctor'));
    });
  });
}
