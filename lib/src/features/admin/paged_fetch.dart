/// Pages through a 0-indexed range-based source, accumulating full pages
/// in order until a short page signals the end, or [maxPages] is reached
/// as a safety cap against an unbounded fetch.
Future<List<T>> fetchAllPages<T>({
  required int pageSize,
  required int maxPages,
  required Future<List<T>> Function(int start, int end) fetchPage,
}) async {
  final all = <T>[];
  for (var page = 0; page < maxPages; page++) {
    final start = page * pageSize;
    final end = start + pageSize - 1;
    final chunk = await fetchPage(start, end);
    all.addAll(chunk);
    if (chunk.length < pageSize) break;
  }
  return all;
}
