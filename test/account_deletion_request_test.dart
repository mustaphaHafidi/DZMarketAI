import 'package:dzmarket/src/models/account_deletion_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('open deletion request blocks new submission', () {
    final request = AccountDeletionRequestSummary.fromJson({
      'id': 1,
      'status': 'processing',
      'requested_at': '2026-04-22T10:00:00Z',
    });

    expect(request.isOpen, isTrue);
    expect(request.canSubmitNewRequest, isFalse);
    expect(request.isTerminal, isFalse);
  });

  test('terminal deletion request allows a new submission later', () {
    final request = AccountDeletionRequestSummary.fromJson({
      'id': 2,
      'status': 'rejected',
      'requested_at': '2026-04-22T10:00:00Z',
      'processed_at': '2026-04-22T11:00:00Z',
      'admin_note': 'Documents insuffisants',
    });

    expect(request.isOpen, isFalse);
    expect(request.isTerminal, isTrue);
    expect(request.canSubmitNewRequest, isTrue);
    expect(request.adminNote, 'Documents insuffisants');
  });
}
