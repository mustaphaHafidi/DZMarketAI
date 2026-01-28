class RateLimiter {
  RateLimiter._();

  static final RateLimiter instance = RateLimiter._();

  final Map<String, _Bucket> _buckets = {};

  Future<void> _wait(String key, Duration minInterval) async {
    final bucket = _buckets.putIfAbsent(key, () => _Bucket());
    final now = DateTime.now();
    final next = bucket.nextAllowedAt;
    if (next != null && next.isAfter(now)) {
      await Future.delayed(next.difference(now));
    }
    bucket.nextAllowedAt = DateTime.now().add(minInterval);
  }

  Future<T> run<T>(
    String key,
    Future<T> Function() action, {
    Duration minInterval = const Duration(milliseconds: 400),
  }) async {
    await _wait(key, minInterval);
    return action();
  }

  Stream<T> stream<T>(
    String key,
    Stream<T> Function() factory, {
    Duration minInterval = const Duration(milliseconds: 400),
  }) {
    return Stream.fromFuture(_wait(key, minInterval))
        .asyncExpand((_) => factory());
  }
}

class _Bucket {
  DateTime? nextAllowedAt;
}
