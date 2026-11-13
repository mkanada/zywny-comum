import 'auth_state.dart';
import 'auth_user.dart';
import 'session_freshness.dart';

/// O estado depois de uma renovação que não chegou ao servidor (D-NEG-OFFLINE):
/// a sessão guardada continua valendo enquanto estiver fresca; passado disso,
/// vale só com o aviso de quando foi confirmada pela última vez.
AuthState renewFailureState(AuthUser user, Object error, DateTime now) {
  if (!SessionFreshness.isFresh(user.lastServerCheckAt, now)) {
    return AuthState.offlineExpired(
      user: user,
      errorMessage: SessionFreshness.messageFor(
        lastVerified: user.lastServerCheckAt,
        now: now,
      ),
    );
  }
  return AuthState.authenticated(
    user,
    errorMessage: 'Não consegui falar com o servidor agora: $error',
  );
}
