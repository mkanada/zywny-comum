import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_auth/zywny_auth.dart';
import 'package:zywny_comum/auth/auth_gate_cubit.dart';

/// Um store que conta as leituras da sessão guardada e pode falhar nelas.
class _LeituraStore extends FakeAuthStore {
  _LeituraStore({this.falha = false}) : super(const AuthState.initializing());

  final bool falha;
  int restoreCalls = 0;

  @override
  Future<void> restore() async {
    restoreCalls++;
    if (falha) throw StateError('sessão ilegível');
  }
}

void main() {
  group('AuthGateCubit', () {
    test('começa com o estado do store', () {
      final store = FakeAuthStore.offlineExpired(nickname: 'Ana');
      final cubit = AuthGateCubit(store: store);
      addTearDown(cubit.close);

      expect(cubit.state, store.state);
      expect(cubit.state.status, AuthStatus.offlineExpired);
    });

    final storeDoEspelho = FakeAuthStore.loggedOut();
    blocTest<AuthGateCubit, AuthState>(
      'espelha cada mudança do store',
      build: () => AuthGateCubit(store: storeDoEspelho),
      act: (_) {
        storeDoEspelho.mudar(const AuthState.initializing());
        storeDoEspelho.mudar(
          const AuthState.unauthenticated(errorMessage: 'Saiu'),
        );
      },
      expect: () => [
        const AuthState.initializing(),
        const AuthState.unauthenticated(errorMessage: 'Saiu'),
      ],
    );

    test('restaurar lê a sessão guardada no store', () async {
      final store = _LeituraStore();
      final cubit = AuthGateCubit(store: store);
      addTearDown(cubit.close);

      await cubit.restaurar();

      expect(store.restoreCalls, 1);
    });

    test(
      'restaurar engole a falha da leitura e deixa o store como está',
      () async {
        final store = _LeituraStore(falha: true);
        final cubit = AuthGateCubit(store: store);
        addTearDown(cubit.close);

        await expectLater(cubit.restaurar(), completes);
        expect(store.restoreCalls, 1);
        expect(cubit.state, const AuthState.initializing());
      },
    );

    test('close tira a assinatura do store', () async {
      final store = FakeAuthStore.loggedOut();
      final cubit = AuthGateCubit(store: store);

      await cubit.close();

      // Sem a assinatura, a mudança não chega ao Cubit fechado (o emit lançaria).
      expect(
        () => store.mudar(const AuthState.initializing()),
        returnsNormally,
      );
      expect(cubit.state, const AuthState.unauthenticated());
    });
  });
}
