import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';

final sessionProvider = Provider<({String? role, bool expired})>((ref) {
  void refresh() => ref.invalidateSelf();
  auth.addListener(refresh);
  ref.onDispose(() => auth.removeListener(refresh));
  return (role: auth.role, expired: auth.expired);
});
