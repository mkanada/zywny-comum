// A tela de reconexão (BL04): a sessão guardada passou dos 7 dias sem rede, e
// o aluno tenta renovar ou troca de conta. Só o botão ocupado e o erro
// mudam aqui; o portão (AuthGateCubit) é quem troca de tela.

import 'package:zywny_auth/zywny_auth.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

class ReconnectState extends Equatable {
  const ReconnectState({this.busy = false, this.error});

  /// Uma tentativa (renovar ou sair) está em curso.
  final bool busy;

  /// O erro da última tentativa, em português.
  final String? error;

  ReconnectState copyWith({
    bool? busy,
    String? error,
    bool limparErro = false,
  }) => ReconnectState(
    busy: busy ?? this.busy,
    error: limparErro ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [busy, error];
}

class ReconnectCubit extends Cubit<ReconnectState> {
  ReconnectCubit({required this.store}) : super(const ReconnectState());

  /// Quem renova a sessão e sai da conta (D01).
  final AuthStore store;

  /// Fala com o servidor para renovar a sessão. Se der certo, o portão abre o
  /// app sozinho.
  Future<void> tentarDeNovo() async {
    emit(state.copyWith(busy: true, limparErro: true));
    try {
      await store.refreshSession();
    } on AuthException catch (e) {
      if (!isClosed) emit(state.copyWith(error: e.message));
    } on Object catch (e) {
      if (!isClosed) {
        emit(state.copyWith(error: 'Não consegui falar com o servidor: $e'));
      }
    } finally {
      if (!isClosed) emit(state.copyWith(busy: false));
    }
  }

  /// Sai da conta guardada, para entrar com outra.
  Future<void> trocarDeConta() async {
    emit(state.copyWith(busy: true, limparErro: true));
    try {
      await store.signOut();
    } on Object catch (e) {
      if (!isClosed) {
        emit(state.copyWith(error: 'Não consegui sair da conta: $e'));
      }
    } finally {
      if (!isClosed) emit(state.copyWith(busy: false));
    }
  }
}
