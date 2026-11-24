import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_auth/zywny_auth.dart';
import 'package:zywny_comum/auth/reconnect_cubit.dart';

/// A renovação recusada na primeira vez e aceita na segunda.
class _RenovacaoDepoisDeUmaFalha extends FakeAuthStore {
  int tentativas = 0;

  @override
  Future<void> refreshSession() async {
    tentativas++;
    if (tentativas == 1) throw const AuthException('Sem rede agora.');
  }
}

/// A renovação que estoura um erro que não é do store.
class _RenovacaoQueEstoura extends FakeAuthStore {
  @override
  Future<void> refreshSession() async => throw StateError('servidor');
}

/// Sair da conta que falha.
class _SairQueFalha extends FakeAuthStore {
  @override
  Future<void> signOut() async => throw StateError('falhou');
}

void main() {
  group('ReconnectState', () {
    test('copyWith troca o campo pedido e limpa o erro quando pedido', () {
      const estado = ReconnectState(busy: true, error: 'Sem rede.');

      expect(estado.copyWith(busy: false).error, 'Sem rede.');
      expect(estado.copyWith(limparErro: true).error, isNull);
      expect(estado.copyWith(limparErro: true).busy, isTrue);
    });
  });

  group('ReconnectCubit', () {
    final storeDaRenovacao = FakeAuthStore.offlineExpired();
    blocTest<ReconnectCubit, ReconnectState>(
      'tentar de novo renova a sessão e solta o botão',
      build: () => ReconnectCubit(store: storeDaRenovacao),
      act: (cubit) => cubit.tentarDeNovo(),
      expect: () => [const ReconnectState(busy: true), const ReconnectState()],
      verify: (_) => expect(storeDaRenovacao.refreshCalls, 1),
    );

    blocTest<ReconnectCubit, ReconnectState>(
      'uma renovação recusada mostra o erro do AuthException',
      build: () => ReconnectCubit(store: _RenovacaoDepoisDeUmaFalha()),
      act: (cubit) => cubit.tentarDeNovo(),
      expect: () => [
        const ReconnectState(busy: true),
        const ReconnectState(busy: true, error: 'Sem rede agora.'),
        const ReconnectState(error: 'Sem rede agora.'),
      ],
    );

    blocTest<ReconnectCubit, ReconnectState>(
      'uma nova tentativa limpa o erro antigo',
      build: () => ReconnectCubit(store: _RenovacaoDepoisDeUmaFalha()),
      act: (cubit) async {
        await cubit.tentarDeNovo();
        await cubit.tentarDeNovo();
      },
      expect: () => [
        const ReconnectState(busy: true),
        const ReconnectState(busy: true, error: 'Sem rede agora.'),
        const ReconnectState(error: 'Sem rede agora.'),
        const ReconnectState(busy: true),
        const ReconnectState(),
      ],
    );

    blocTest<ReconnectCubit, ReconnectState>(
      'um erro que não é do store vira "Não consegui falar com o servidor"',
      build: () => ReconnectCubit(store: _RenovacaoQueEstoura()),
      act: (cubit) => cubit.tentarDeNovo(),
      expect: () => [
        const ReconnectState(busy: true),
        const ReconnectState(
          busy: true,
          error: 'Não consegui falar com o servidor: Bad state: servidor',
        ),
        const ReconnectState(
          error: 'Não consegui falar com o servidor: Bad state: servidor',
        ),
      ],
    );

    final storeDaSaida = FakeAuthStore.offlineExpired();
    blocTest<ReconnectCubit, ReconnectState>(
      'trocar de conta sai da conta e solta o botão',
      build: () => ReconnectCubit(store: storeDaSaida),
      act: (cubit) => cubit.trocarDeConta(),
      expect: () => [const ReconnectState(busy: true), const ReconnectState()],
      verify: (_) => expect(storeDaSaida.signOutCalls, 1),
    );

    blocTest<ReconnectCubit, ReconnectState>(
      'uma saída que falha mostra "Não consegui sair da conta"',
      build: () => ReconnectCubit(store: _SairQueFalha()),
      act: (cubit) => cubit.trocarDeConta(),
      expect: () => [
        const ReconnectState(busy: true),
        const ReconnectState(
          busy: true,
          error: 'Não consegui sair da conta: Bad state: falhou',
        ),
        const ReconnectState(
          error: 'Não consegui sair da conta: Bad state: falhou',
        ),
      ],
    );
  });
}
