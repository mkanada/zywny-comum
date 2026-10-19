import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_state.dart';
import 'auth_store.dart';
import 'auth_user.dart';
import 'id_token.dart';
import 'session_freshness.dart';
import 'session_storage.dart';

/// O login com o SDK do Firebase: Android e Web (D01). O Linux e o Windows não
/// têm plugin nativo do Firebase — lá quem entra é o
/// [FirebaseRestAuthStore], pelo navegador do sistema.
///
/// A regra dos 7 dias sem rede (D-NEG-OFFLINE) é a mesma dos outros
/// caminhos: a sessão guardada vale até uma semana depois da última vez que o
/// servidor respondeu.
class FirebaseSdkAuthStore extends AuthStoreBase implements AuthStore {
  FirebaseSdkAuthStore({
    fb.FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    SharedPreferencesAsync? prefs,
    Future<void> Function()? ensureInitialized,
    DateTime Function()? clock,
    this.googleClientId,
    this.googleServerClientId,
  }) : _auth = auth ?? fb.FirebaseAuth.instance,
       _google = googleSignIn ?? GoogleSignIn.instance,
       _storage = SessionStorage(prefs: prefs),
       _ensureInitialized = ensureInitialized ?? _defaultInitialize,
       _clock = clock ?? DateTime.now;

  /// O OAuth Client ID do Android (o do tipo "Web" é lido do
  /// `google-services.json`).
  final String? googleClientId;

  /// O `server_client_id` do Google (o mesmo que vai no `firebase_options`).
  final String? googleServerClientId;

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _google;
  final SessionStorage _storage;
  final Future<void> Function() _ensureInitialized;
  final DateTime Function() _clock;

  bool _googleInitialized = false;

  @override
  Future<void> restore() async {
    final user = await _storage.read();
    if (user == null) {
      setState(const AuthState.unauthenticated());
      return;
    }
    final now = _clock();
    if (!SessionFreshness.isFresh(user.lastServerCheckAt, now)) {
      setState(
        AuthState.offlineExpired(
          user: user,
          errorMessage: SessionFreshness.messageFor(
            lastVerified: user.lastServerCheckAt,
            now: now,
          ),
        ),
      );
      return;
    }
    setState(AuthState.authenticated(user));
  }

  @override
  Future<void> signInWithProvider(SocialProvider provider) async {
    try {
      await _ensureInitialized();
      final user = switch (provider) {
        SocialProvider.google => await _signInWithGoogle(),
        _ => throw const AuthException(
          'Esse provedor de login ainda não está pronto.',
        ),
      };
      await _storage.write(user);
      setState(AuthState.authenticated(user));
    } on AuthException catch (e) {
      setState(AuthState.unauthenticated(errorMessage: e.message));
    } on fb.FirebaseAuthException catch (e) {
      setState(AuthState.unauthenticated(errorMessage: e.message));
    } on Object catch (e) {
      setState(
        AuthState.unauthenticated(errorMessage: 'Não consegui entrar: $e'),
      );
    }
  }

  @override
  Future<void> refreshSession() async {
    final user = currentUser;
    if (user == null) {
      setState(
        const AuthState.unauthenticated(
          errorMessage: 'Não há sessão para renovar.',
        ),
      );
      return;
    }
    try {
      await _ensureInitialized();
      final firebaseUser = _auth.currentUser;
      if (firebaseUser == null) {
        throw const AuthException('A sessão do Firebase não está mais aqui.');
      }
      final idToken = await firebaseUser.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('O Firebase não devolveu o token novo.');
      }
      final now = _clock();
      final updated = user.copyWith(
        idToken: idToken,
        refreshToken: firebaseUser.refreshToken ?? user.refreshToken,
        idTokenExpiresAt: idTokenExpiresAt(idToken),
        lastServerCheckAt: now,
      );
      await _storage.write(updated);
      setState(AuthState.authenticated(updated));
    } on Object catch (e) {
      // A rede falhou: a sessão guardada continua valendo enquanto estiver
      // fresca (D-NEG-OFFLINE).
      final now = _clock();
      if (!SessionFreshness.isFresh(user.lastServerCheckAt, now)) {
        setState(
          AuthState.offlineExpired(
            user: user,
            errorMessage: SessionFreshness.messageFor(
              lastVerified: user.lastServerCheckAt,
              now: now,
            ),
          ),
        );
      } else {
        setState(
          AuthState.authenticated(
            user,
            errorMessage: 'Não consegui falar com o servidor agora: $e',
          ),
        );
      }
    }
  }

  @override
  Future<void> updateNickname(String nickname) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException(
        'Não há ninguém conectado para ter um apelido.',
      );
    }
    final updated = await saveNickname(_storage, user, nickname);
    setState(AuthState.authenticated(updated));
  }

  @override
  Future<void> signOut() async {
    try {
      await _ensureInitialized();
      await _auth.signOut();
      await _google.signOut();
    } on Object {
      // Sem rede (ou sem o plugin): a sessão local é apagada assim mesmo.
    }
    await _storage.clear();
    setState(const AuthState.unauthenticated());
  }

  @override
  Future<void> deleteAccount() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      await firebaseUser.delete();
    }
    await _storage.clear();
    setState(const AuthState.unauthenticated());
  }

  /// Entra com o Google: na Web, o popup do Firebase; no Android, o seletor
  /// nativo do `google_sign_in` (D00).
  Future<AuthUser> _signInWithGoogle() async {
    if (kIsWeb) {
      final credential = await _auth.signInWithPopup(fb.GoogleAuthProvider());
      return _userFrom(credential.user);
    }
    await _initGoogle();
    final account = await _google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException('O Google não devolveu o token de identidade.');
    }
    final credential = fb.GoogleAuthProvider.credential(idToken: idToken);
    final result = await _auth.signInWithCredential(credential);
    return _userFrom(result.user);
  }

  /// O `google_sign_in` só pode ser inicializado uma vez por processo.
  Future<void> _initGoogle() async {
    if (_googleInitialized) return;
    await _google.initialize(
      clientId: googleClientId,
      serverClientId: googleServerClientId,
    );
    _googleInitialized = true;
  }

  Future<AuthUser> _userFrom(fb.User? user) async {
    if (user == null) {
      throw const AuthException('O Firebase não devolveu o usuário.');
    }
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException('O Firebase não devolveu o token.');
    }
    final now = _clock();
    final previous = await _storage.read();
    return AuthUser(
      uid: user.uid,
      providerId: SocialProvider.google.id,
      idToken: idToken,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      refreshToken: user.refreshToken,
      idTokenExpiresAt: idTokenExpiresAt(idToken),
      lastServerCheckAt: now,
      // O apelido é do Zywny: ele só continua se for a mesma pessoa.
      nickname: previous?.uid == user.uid ? previous?.nickname : null,
    );
  }

  /// Garante que o app inicializou o Firebase (quem faz isso é o `main`, no
  /// D03).
  static Future<void> _defaultInitialize() async {
    if (Firebase.apps.isEmpty) {
      throw const AuthException('O Firebase não foi inicializado neste app.');
    }
  }
}
