import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_auth/zywny_auth.dart';
import 'package:zywny_comum/auth/sign_in_cubit.dart';

/// O login recusado pelo provedor, com a mensagem que o store daria.
class _LoginRecusado extends FakeAuthStore {
  @override
  Future<void> signInWithProvider(SocialProvider provider) async {
    throw const AuthException('Login recusado pelo Google.');
  }
}

/// Um login que estoura um erro que não é do store (rede, por exemplo).
class _LoginQueEstoura extends FakeAuthStore {
  @override
  Future<void> signInWithProvider(SocialProvider provider) async {
    throw StateError('rede');
  }
}

/// Um login que só termina quando o teste manda.
class _LoginLento extends FakeAuthStore {
  final Completer<void> login = Completer<void>();

  @override
  Future<void> signInWithProvider(SocialProvider provider) => login.future;
}

void main() {
  group('SignInState', () {
    test('a mensagem é o erro do login, e o aviso do store só sem ele', () {
      const comErro = SignInState(error: 'Erro', storeMessage: 'Aviso');
      const soAviso = SignInState(storeMessage: 'Aviso');

      expect(comErro.message, 'Erro');
      expect(soAviso.message, 'Aviso');
      expect(const SignInState().message, isNull);
    });

    test('é igual pelo valor (Equatable)', () {
      expect(
        const SignInState(busy: SocialProvider.google),
        equals(const SignInState(busy: SocialProvider.google)),
      );
      expect(
        const SignInState(busy: SocialProvider.google),
        isNot(equals(const SignInState(busy: SocialProvider.apple))),
      );
    });
  });

  group('SignInCubit', () {
    test('começa sem login em curso e com o aviso que o store guarda', () {
      final store = FakeAuthStore(
        const AuthState.unauthenticated(errorMessage: 'Sessão encerrada.'),
      );
      final cubit = SignInCubit(store: store);
      addTearDown(cubit.close);

      expect(cubit.state.busy, isNull);
      expect(cubit.state.error, isNull);
      expect(cubit.state.message, 'Sessão encerrada.');
    });

    final storeDoAviso = FakeAuthStore.loggedOut();
    blocTest<SignInCubit, SignInState>(
      'um aviso novo do store chega à tela',
      build: () => SignInCubit(store: storeDoAviso),
      act: (_) => storeDoAviso.mudar(
        const AuthState.unauthenticated(errorMessage: 'Faz 7 dias.'),
      ),
      expect: () => [const SignInState(storeMessage: 'Faz 7 dias.')],
    );

    final storeDoLogin = FakeAuthStore.loggedOut();
    blocTest<SignInCubit, SignInState>(
      'entrar marca o provedor em curso e solta ao terminar',
      build: () => SignInCubit(store: storeDoLogin),
      act: (cubit) => cubit.entrar(SocialProvider.google),
      expect: () => [
        const SignInState(busy: SocialProvider.google),
        const SignInState(),
      ],
      verify: (_) {
        expect(storeDoLogin.signInCalls, 1);
        expect(storeDoLogin.lastProvider, SocialProvider.google);
      },
    );

    blocTest<SignInCubit, SignInState>(
      'um login recusado mostra a mensagem do AuthException',
      build: () => SignInCubit(store: _LoginRecusado()),
      act: (cubit) => cubit.entrar(SocialProvider.google),
      expect: () => [
        const SignInState(busy: SocialProvider.google),
        const SignInState(
          busy: SocialProvider.google,
          error: 'Login recusado pelo Google.',
        ),
        const SignInState(error: 'Login recusado pelo Google.'),
      ],
    );

    blocTest<SignInCubit, SignInState>(
      'um erro que não é do store vira "Não consegui entrar"',
      build: () => SignInCubit(store: _LoginQueEstoura()),
      act: (cubit) => cubit.entrar(SocialProvider.apple),
      expect: () => [
        const SignInState(busy: SocialProvider.apple),
        const SignInState(
          busy: SocialProvider.apple,
          error: 'Não consegui entrar: Bad state: rede',
        ),
        const SignInState(error: 'Não consegui entrar: Bad state: rede'),
      ],
    );

    test(
      'se a tela fechar antes do login terminar, não emite nem lança',
      () async {
        final store = _LoginLento();
        final cubit = SignInCubit(store: store);

        final entrada = cubit.entrar(SocialProvider.google);
        await cubit.close();
        store.login.completeError(const AuthException('tarde demais'));

        await expectLater(entrada, completes);
        expect(cubit.isClosed, isTrue);
        expect(
          cubit.state.busy,
          SocialProvider.google,
          reason: 'o estado não mudou depois do close',
        );
      },
    );

    test('close tira a assinatura do store', () async {
      final store = FakeAuthStore.loggedOut();
      final cubit = SignInCubit(store: store);

      await cubit.close();

      // Sem a assinatura, o aviso novo não chega ao Cubit fechado (o emit lançaria).
      expect(
        () => store.mudar(
          const AuthState.unauthenticated(errorMessage: 'Faz 7 dias.'),
        ),
        returnsNormally,
      );
    });
  });
}
