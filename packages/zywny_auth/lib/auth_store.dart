import 'package:flutter/foundation.dart';

import 'auth_state.dart';
import 'auth_user.dart';

/// O contrato de autenticação do zywny (D01). Os dois caminhos de login
/// (SDK do Firebase no Android/Web e REST no desktop) e o [FakeAuthStore] dos
/// testes cumprem este mesmo contrato.
abstract interface class AuthStore extends ValueListenable<AuthState> {
  /// Quem está conectado agora (ou `null`).
  AuthUser? get currentUser;

  /// Lê a sessão guardada no aparelho e põe o app no estado certo. É a
  /// primeira coisa que o app chama ao abrir (D02).
  Future<void> restore();

  /// Entra com uma rede social. No desktop só o Google funciona por ora: os
  /// outros provedores do botão ainda não têm o caminho de loopback.
  Future<void> signInWithProvider(SocialProvider provider);

  /// Fala com o servidor para renovar o `idToken` e a marca de "servidor
  /// visto" (a regra dos 7 dias). Sem rede, a sessão guardada continua valendo
  /// enquanto estiver fresca.
  Future<void> refreshSession();

  /// Troca o apelido da pessoa (D-NEG-PRIVACIDADE). Fica no aparelho.
  Future<void> updateNickname(String nickname);

  /// Sai da conta (o `refreshToken` é revogado no servidor, quando há rede).
  Future<void> signOut();

  /// Apaga a conta no servidor e os dados locais (exigência da LGPD,
  /// D-NEG-PRIVACIDADE).
  Future<void> deleteAccount();
}

/// A base dos dois stores: um [ValueNotifier] com o estado e a regra de só
/// avisar quando o estado muda.
abstract class AuthStoreBase extends ValueNotifier<AuthState>
    implements AuthStore {
  AuthStoreBase() : super(const AuthState.initializing());

  @override
  AuthUser? get currentUser => value.user;

  /// Troca o estado e avisa quem escuta (só quando o estado é outro).
  void setState(AuthState next) {
    if (next != value) value = next;
  }
}
