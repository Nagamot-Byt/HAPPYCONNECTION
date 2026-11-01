import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/features/ui/home_models.dart';

void main() {
  group('ConnectionLogStore', () {
    test('keeps only the most recent entries', () {
      final store = ConnectionLogStore(maxEntries: 3);

      for (var i = 0; i < 5; i++) {
        store.add('line $i');
      }

      expect(store.entries.length, 3);
      expect(store.formatted.first, contains('line 2'));
      expect(store.formatted.last, contains('line 4'));
    });

    test('records error level and formats timestamps', () {
      final store = ConnectionLogStore(
        clock: () => DateTime(2026, 10, 30, 8, 9, 10, 123),
      );

      store.add('fallo', isError: true);

      expect(store.entries.single.isError, isTrue);
      expect(store.formatted.single, startsWith('[08:09:10.123]'));
    });

    test('clear removes all entries', () {
      final store = ConnectionLogStore()..add('one');

      store.clear();

      expect(store.entries, isEmpty);
    });
  });
}
