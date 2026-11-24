import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_auth/zywny_auth.dart';
import 'package:zywny_comum/auth/nickname_cubit.dart';

/// Um apelido que o store recusa (por exemplo, já usado).
class _ApelidoRecusado extends FakeAuthStore {
  @override
  Future<void> updateNickname(String nickname) async {
    throw const AuthException('Esse apelido já existe.');
  }
}

/// Guardar que estoura um erro que não é do store.
class _ApelidoQueEstoura extends FakeAuthStore {
  @override
  Future<void> updateNickname(String nickname) async =>
      throw StateError('disco');
}

void main() {
  group('NicknameState', () {
    test('podeContinuar exige apelido de verdade, aceite e sem envio', () {
      expect(const NicknameState().podeContinuar, isFalse);
      expect(
        const NicknameState(nickname: 'Ana', accepted: false).podeContinuar,
        isFalse,
      );
      expect(
        const NicknameState(nickname: '   ', accepted: true).podeContinuar,
        isFalse,
        reason: 'espaço não é apelido',
      );
      expect(
        const NicknameState(nickname: 'Ana', accepted: true).podeContinuar,
        isTrue,
      );
      expect(
        const NicknameState(
          nickname: 'Ana',
          accepted: true,
          busy: true,
        ).podeContinuar,
        isFalse,
        reason: 'com envio em curso, o botão fica desligado',
      );
    });

    test('copyWith troca o campo pedido e limpa o erro quando pedido', () {
      const estado = NicknameState(nickname: 'Ana', error: 'Erro');

      expect(estado.copyWith(accepted: true).nickname, 'Ana');
      expect(estado.copyWith(accepted: true).error, 'Erro');
      expect(estado.copyWith(limparErro: true).error, isNull);
    });
  });

  group('NicknameCubit', () {
    final storeDaEdicao = FakeAuthStore.loggedIn();
    blocTest<NicknameCubit, NicknameState>(
      'editarApelido guarda o texto digitado',
      build: () => NicknameCubit(store: storeDaEdicao),
      act: (cubit) => cubit.editarApelido('Ana'),
      expect: () => [const NicknameState(nickname: 'Ana')],
    );

    final storeDoAceite = FakeAuthStore.loggedIn();
    blocTest<NicknameCubit, NicknameState>(
      'mudarAceite marca o aceite',
      build: () => NicknameCubit(store: storeDoAceite),
      act: (cubit) => cubit.mudarAceite(true),
      expect: () => [const NicknameState(accepted: true)],
    );

    final storeSemAceite = FakeAuthStore.loggedIn();
    blocTest<NicknameCubit, NicknameState>(
      'continuar sem o aceite não guarda nada',
      build: () => NicknameCubit(store: storeSemAceite),
      act: (cubit) async {
        cubit.editarApelido('Ana');
        await cubit.continuar();
      },
      expect: () => [const NicknameState(nickname: 'Ana')],
      verify: (_) => expect(storeSemAceite.nicknameCalls, 0),
    );

    final storeDoApelido = FakeAuthStore.loggedIn();
    blocTest<NicknameCubit, NicknameState>(
      'continuar com apelido e aceite guarda o apelido como digitado',
      build: () => NicknameCubit(store: storeDoApelido),
      act: (cubit) async {
        cubit.editarApelido('Ana');
        cubit.mudarAceite(true);
        await cubit.continuar();
      },
      expect: () => [
        const NicknameState(nickname: 'Ana'),
        const NicknameState(nickname: 'Ana', accepted: true),
        const NicknameState(nickname: 'Ana', accepted: true, busy: true),
        const NicknameState(nickname: 'Ana', accepted: true),
      ],
      verify: (_) {
        expect(storeDoApelido.nicknameCalls, 1);
        expect(storeDoApelido.lastNickname, 'Ana');
      },
    );

    blocTest<NicknameCubit, NicknameState>(
      'um apelido recusado mostra o erro do AuthException',
      build: () => NicknameCubit(store: _ApelidoRecusado()),
      act: (cubit) async {
        cubit.editarApelido('Ana');
        cubit.mudarAceite(true);
        await cubit.continuar();
      },
      skip: 2,
      expect: () => [
        const NicknameState(nickname: 'Ana', accepted: true, busy: true),
        const NicknameState(
          nickname: 'Ana',
          accepted: true,
          busy: true,
          error: 'Esse apelido já existe.',
        ),
        const NicknameState(
          nickname: 'Ana',
          accepted: true,
          error: 'Esse apelido já existe.',
        ),
      ],
    );

    blocTest<NicknameCubit, NicknameState>(
      'um erro que não é do store vira "Não consegui guardar"',
      build: () => NicknameCubit(store: _ApelidoQueEstoura()),
      act: (cubit) async {
        cubit.editarApelido('Ana');
        cubit.mudarAceite(true);
        await cubit.continuar();
      },
      skip: 2,
      expect: () => [
        const NicknameState(nickname: 'Ana', accepted: true, busy: true),
        const NicknameState(
          nickname: 'Ana',
          accepted: true,
          busy: true,
          error: 'Não consegui guardar: Bad state: disco',
        ),
        const NicknameState(
          nickname: 'Ana',
          accepted: true,
          error: 'Não consegui guardar: Bad state: disco',
        ),
      ],
    );
  });
}
