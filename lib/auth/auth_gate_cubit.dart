// O portão da autenticação (BL04): espelha o estado do AuthStore num Cubit,
// para o AuthGate reconstruir a tela quando a sessão muda. O store é um
// ValueListenable (AuthStoreBase é um ValueNotifier), então o Cubit assina
// com addListener e tira a assinatura no close().

import 'package:zywny_auth/zywny_auth.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

/// O estado do portão é o próprio estado do store: o portão só decide o que
/// mostrar (entrar, carregar, pedir conexão, a tela de entrada).
class AuthGateCubit extends Cubit<AuthState> {
  AuthGateCubit({required this.store}) : super(store.value) {
    store.addListener(_aoMudarStore);
  }

  /// Quem guarda a sessão (D01). O Cubit só espelha o que ele diz.
  final AuthStore store;

  void _aoMudarStore() => emit(store.value);

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
  Future<void> close() {
    store.removeListener(_aoMudarStore);
    return super.close();
  }
}
