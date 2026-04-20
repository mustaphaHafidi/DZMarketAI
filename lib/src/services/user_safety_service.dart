import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserSafetyService {
  UserSafetyService();

  static const supportEmail = 'support@dzmarket.pro';

  Future<bool> isBlocked(String otherUserId) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null || otherUserId.isEmpty) return false;
    final row = await supabase
        .from('user_blocks')
        .select('user_id')
        .eq('user_id', currentUserId)
        .eq('blocked_user_id', otherUserId)
        .maybeSingle();
    return row != null;
  }

  Future<void> blockUser(String otherUserId) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      throw const AuthException('login_required');
    }
    final safeOtherUserId = InputSanitizer.sanitizeId(
      otherUserId,
      maxLength: 64,
    );
    if (safeOtherUserId.isEmpty || safeOtherUserId == currentUserId) {
      throw const FormatException('invalid_user');
    }
    await supabase.from('user_blocks').upsert({
      'user_id': currentUserId,
      'blocked_user_id': safeOtherUserId,
    });
  }

  Future<void> unblockUser(String otherUserId) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      throw const AuthException('login_required');
    }
    await supabase
        .from('user_blocks')
        .delete()
        .eq('user_id', currentUserId)
        .eq('blocked_user_id', otherUserId);
  }

  Future<void> reportUser({
    required String reportedUserId,
    required String reason,
    String source = 'profile',
  }) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      throw const AuthException('login_required');
    }
    final safeReportedUserId = InputSanitizer.sanitizeId(
      reportedUserId,
      maxLength: 64,
    );
    final safeReason = InputSanitizer.sanitizeText(reason, maxLength: 500);
    if (safeReportedUserId.isEmpty || safeReportedUserId == currentUserId) {
      throw const FormatException('invalid_user');
    }
    if (safeReason.isEmpty) {
      throw const FormatException('missing_reason');
    }
    try {
      await supabase.rpc(
        'submit_user_report',
        params: {
          'p_reported_user_id': safeReportedUserId,
          'p_reason': safeReason,
          'p_source': _normalizeSource(source),
        },
      );
    } on PostgrestException catch (error) {
      final missingRpc =
          error.code == 'PGRST202' ||
          error.code == '42883' ||
          error.message.contains('submit_user_report');
      if (!missingRpc) rethrow;
      await supabase.from('user_reports').insert({
        'reporter_id': currentUserId,
        'reported_user_id': safeReportedUserId,
        'reason': safeReason,
        'source': _normalizeSource(source),
      });
    }
  }

  String _normalizeSource(String source) {
    switch (source.trim().toLowerCase()) {
      case 'chat':
      case 'profile':
      case 'listing':
        return source.trim().toLowerCase();
      default:
        return 'profile';
    }
  }
}
