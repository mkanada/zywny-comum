// O primeiro acesso (BL04): o apelido e o aceite da política de privacidade.
// O texto do apelido mora aqui (o campo não tem controller): o Cubit precisa
// dele para liberar o botão e para guardar.

import 'package:zywny_auth/zywny_auth.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

class NicknameState extends Equatable {
  const NicknameState({
    this.nickname = '',
    this.accepted = false,
    this.busy = false,
    this.error,
  });

  /// O apelido como foi digitado (sem cortar os espaços: é o que se guarda).
  final String nickname;

  /// A pessoa aceitou o uso dos dados de estudo.
  final bool accepted;

  /// O apelido está sendo guardado.
  final bool busy;

  /// O erro da última tentativa de guardar, em português.
  final String? error;

  /// Continua só com um apelido de verdade, o aceite e sem envio em curso.
  bool get podeContinuar => nickname.trim().isNotEmpty && accepted && !busy;

  NicknameState copyWith({
    String? nickname,
    bool? accepted,
    bool? busy,
    String? error,
    bool limparErro = false,
  }) => NicknameState(
    nickname: nickname ?? this.nickname,
    accepted: accepted ?? this.accepted,
    busy: busy ?? this.busy,
    error: limparErro ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [nickname, accepted, busy, error];
}

class NicknameCubit extends Cubit<NicknameState> {
  NicknameCubit({required this.store}) : super(const NicknameState());

  /// Quem guarda o apelido (D-NEG-PRIVACIDADE).
  final AuthStore store;

  void editarApelido(String texto) => emit(state.copyWith(nickname: texto));

  void mudarAceite(bool aceito) => emit(state.copyWith(accepted: aceito));

  /// Guarda o apelido e segue. Sem apelido, sem aceite ou com envio em curso,
  /// não faz nada (o botão já está desligado, mas o Enter também chega aqui).
  Future<void> continuar() async {
    if (!state.podeContinuar) return;
    emit(state.copyWith(busy: true, limparErro: true));
    try {
      await store.updateNickname(state.nickname);
    } on AuthException catch (e) {
      if (!isClosed) emit(state.copyWith(error: e.message));
    } on Object catch (e) {
      if (!isClosed) emit(state.copyWith(error: 'Não consegui guardar: $e'));
    } finally {
      if (!isClosed) emit(state.copyWith(busy: false));
    }
  }
}
