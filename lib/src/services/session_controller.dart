import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionController extends ChangeNotifier {
  SessionController._() {
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (event) {
        _session = event.session;
        notifyListeners();
      },
    );
  }

  static final SessionController instance = SessionController._();

  Session? _session;
  late final StreamSubscription<AuthState> _subscription;

  Session? get session => _session;
  User? get user => _session?.user;
  bool get isAuthenticated => _session?.user != null;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
