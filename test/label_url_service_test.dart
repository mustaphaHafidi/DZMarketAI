import 'package:dzmarket/src/services/label_service.dart';
import 'package:dzmarket/src/services/label_url_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLabelService extends LabelService {
  _FakeLabelService(this._responseByOrderId);

  final Map<String, Map<String, dynamic>?> _responseByOrderId;
  int callCount = 0;

  @override
  Future<Map<String, dynamic>?> generateLabel(
    String orderId, {
    Map<String, dynamic>? request,
    bool sendMessage = false,
  }) async {
    callCount += 1;
    return _responseByOrderId[orderId];
  }
}

void main() {
  test('keeps valid external label url without regenerating it', () async {
    final fakeService = _FakeLabelService(const {});
    final service = LabelUrlService(labelService: fakeService);
    final futureExpiry = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 4))
        .toIso8601String();
    final rawUrl =
        'https://files.zrexpress.app/labels/demo.pdf?sv=2024-01-01&se=$futureExpiry';

    final uri = await service.resolveFreshLabelUri(rawUrl, orderId: '135');

    expect(uri?.toString(), rawUrl);
    expect(fakeService.callCount, 0);
  });

  test('refreshes expired external zrexpress label from order endpoint', () async {
    final fakeService = _FakeLabelService({
      '135': {
        'label_url':
            'https://api.dzmarket.pro/storage/v1/object/sign/labels/test/fresh.pdf?token=fresh-token',
      },
    });
    final service = LabelUrlService(labelService: fakeService);
    final expired = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 2))
        .toIso8601String();
    final rawUrl =
        'https://files.zrexpress.app/labels/demo.pdf?sv=2024-01-01&se=$expired';

    final uri = await service.resolveFreshLabelUri(rawUrl, orderId: '135');

    expect(
      uri?.toString(),
      'https://api.dzmarket.pro/storage/v1/object/sign/labels/test/fresh.pdf?token=fresh-token',
    );
    expect(fakeService.callCount, 1);
  });

  test(
    'returns null when an expired external label cannot be refreshed',
    () async {
      final fakeService = _FakeLabelService(const {});
      final service = LabelUrlService(labelService: fakeService);
      final expired = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .toIso8601String();
      final rawUrl =
          'https://files.zrexpress.app/labels/demo.pdf?sv=2024-01-01&se=$expired';

      final uri = await service.resolveFreshLabelUri(rawUrl, orderId: '135');

      expect(uri, isNull);
      expect(fakeService.callCount, 1);
    },
  );
}
