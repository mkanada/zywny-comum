// O portão da autenticação (BL04, BL09): o store já é um Cubit, então o portão
// só espelha o estado dele pelo `stream`, para o AuthGate reconstruir a tela
// quando a sessão muda. A assinatura é cancelada no close(). Ele também é quem
// lê a sessão guardada ao abrir (restaurar).

import 'dart:async';

import 'package:zywny_auth/zywny_auth.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

/// O estado do portão é o próprio estado do store: o portão só decide o que
/// mostrar (entrar, carregar, pedir conexão, a tela de entrada).
class AuthGateCubit extends Cubit<AuthState> {
  AuthGateCubit({required this.store}) : super(store.state) {
    _assinatura = store.stream.listen(_aoMudarStore);
  }

  /// Quem guarda a sessão (D01). O Cubit só espelha o que ele diz.
  final AuthStore store;

  late final StreamSubscription<AuthState> _assinatura;

  void _aoMudarStore(AuthState estado) {
    if (!isClosed) emit(estado);
  }

  /// Lê a sessão guardada no aparelho. Enquanto isso roda, o estado é
  /// `initializing` e a tela mostra o carregando.
  Future<void> restaurar() async {
    try {
      await store.restore();
    } on Object {
      // A sessão guardada não pôde ser lida: o store fica como está, e o app
      // mostra o que ele disser (a tela de entrada, em geral).
    }
  }

  @override
  Future<void> close() async {
    await _assinatura.cancel();
    return super.close();
  }
}
