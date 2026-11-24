import 'package:zywny_bloc/zywny_bloc.dart';

import 'auth_state.dart';
import 'auth_user.dart';

/// O contrato de autenticação do zywny (D01). Os dois caminhos de login
/// (SDK do Firebase no Android/Web e REST no desktop) e o [FakeAuthStore] dos
/// testes cumprem este mesmo contrato. O estado é lido com `state` e ouvido
/// pelo `stream` (BL09: o store é um Cubit).
abstract interface class AuthStore implements StateStreamable<AuthState> {
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

/// A base dos stores (e do fake dos testes): um Cubit com o estado da
/// autenticação. O `emit` já ignora o estado igual ao atual, então quem ouve
/// o `stream` só recebe mudança de verdade.
abstract class AuthStoreBase extends Cubit<AuthState> implements AuthStore {
  AuthStoreBase() : super(const AuthState.initializing());

  @override
  AuthUser? get currentUser => state.user;

  /// Troca o estado e avisa quem escuta. (Não se chama `setState`: o nome
  /// seria confundido com o do widget.)
  void mudar(AuthState next) => emit(next);
}
