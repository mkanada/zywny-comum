// A tela de entrada (BL04, BL09): quem está entrando agora, o erro do último
// login e o aviso que o store guarda (o login recusado, a sessão vencida). O
// Cubit assina o `stream` do store e cancela a assinatura no close().

import 'dart:async';

import 'package:zywny_auth/zywny_auth.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

class SignInState extends Equatable {
  const SignInState({this.busy, this.error, this.storeMessage});

  /// O provedor cujo login está em curso (o botão dele mostra o carregando).
  final SocialProvider? busy;

  /// O erro do login que acabou de falhar, em português.
  final String? error;

  /// O aviso que o store guarda (`AuthState.errorMessage`).
  final String? storeMessage;

  /// O que a tela mostra: o erro do login, quando há; senão, o aviso do store.
  String? get message => error ?? storeMessage;

  @override
  List<Object?> get props => [busy, error, storeMessage];
}

/// Conduz a tela de entrada. Cada troca de estado põe o estado inteiro (o
/// busy e o erro voltam a nulo, então não cabe um `copyWith` simples).
class SignInCubit extends Cubit<SignInState> {
  SignInCubit({required this.store})
    : super(SignInState(storeMessage: store.state.errorMessage)) {
    _assinatura = store.stream.listen(_aoMudarStore);
  }

  /// Quem faz o login e guarda a sessão (D01).
  final AuthStore store;

  late final StreamSubscription<AuthState> _assinatura;

  void _aoMudarStore(AuthState _) {
    if (!isClosed) _emitir(busy: state.busy, error: state.error);
  }

  void _emitir({SocialProvider? busy, String? error}) => emit(
    SignInState(
      busy: busy,
      error: error,
      storeMessage: store.state.errorMessage,
    ),
  );

  /// Entra com um provedor. O botão dele fica em carregando até o login acabar,
  /// com sucesso ou com erro.
  Future<void> entrar(SocialProvider provider) async {
    _emitir(busy: provider);
    try {
      await store.signInWithProvider(provider);
    } on AuthException catch (e) {
      if (!isClosed) _emitir(busy: state.busy, error: e.message);
    } on Object catch (e) {
      if (!isClosed) {
        _emitir(busy: state.busy, error: 'Não consegui entrar: $e');
      }
    } finally {
      if (!isClosed) _emitir(error: state.error);
    }
  }

  @override
  Future<void> close() async {
    await _assinatura.cancel();
    return super.close();
  }
}
