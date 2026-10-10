import 'package:dzmarket/src/features/admin/paged_fetch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fetchAllPages', () {
    test(
      'accumulates every full page in order and stops on the first '
      'short page',
      () async {
        final source = List.generate(7, (i) => 'item-$i');
        final calls = <List<int>>[];

        final result = await fetchAllPages<String>(
          pageSize: 3,
          maxPages: 10,
          fetchPage: (start, end) async {
            calls.add([start, end]);
            final slice = source
                .skip(start)
                .take(end - start + 1)
                .toList();
            return slice;
          },
        );

        expect(result, source);
        // 3 pages: [0,2] (3 items), [3,5] (3 items), [6,8] (1 item, short).
        expect(calls, [
          [0, 2],
          [3, 5],
          [6, 8],
        ]);
      },
    );

    test('a single short first page means only one fetch happens', () async {
      var callCount = 0;
      final result = await fetchAllPages<int>(
        pageSize: 500,
        maxPages: 20,
        fetchPage: (start, end) async {
          callCount++;
          return [1, 2, 3];
        },
      );

      expect(result, [1, 2, 3]);
      expect(callCount, 1);
    });

    test(
      'stops at maxPages even if every page keeps coming back full, so '
      'the fetch can never run unbounded',
      () async {
        var callCount = 0;
        final result = await fetchAllPages<int>(
          pageSize: 2,
          maxPages: 4,
          fetchPage: (start, end) async {
            callCount++;
            return [start, end]; // always exactly pageSize items
          },
        );

        expect(callCount, 4);
        expect(result.length, 8);
      },
    );
  });
}
