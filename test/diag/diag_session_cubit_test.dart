import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/diag/diag_screens.dart';
import 'package:zywny_diag/diag_log.dart';

void main() {
  late MemoryDiagStorage store;

  setUp(() async {
    store = MemoryDiagStorage();
    await DiagLog.init(storage: store, installHandlers: false);
  });
  tearDown(DiagLog.reset);

  // O texto de todas as sessões (o `app` não é sessão).
  String sessoes() => store
      .keys()
      .where((k) => k != 'app')
      .map((k) => store.read(k))
      .join('\n');

  int abertas() => RegExp('#sessao ').allMatches(sessoes()).length;

  group('DiagSessionState', () {
    test('é igual pelo valor (Equatable)', () {
      expect(
        const DiagSessionState(kind: 'exercicio', name: '34d'),
        const DiagSessionState(kind: 'exercicio', name: '34d'),
      );
      expect(
        const DiagSessionState(kind: 'exercicio', name: '34d'),
        isNot(const DiagSessionState(kind: 'exercicio', name: '35a')),
      );
    });
  });

  group('DiagSessionCubit', () {
    test('abre a sessão na construção', () {
      final cubit = DiagSessionCubit(kind: 'exercicio', name: '34d');
      addTearDown(cubit.close);

      expect(sessoes(), contains('#sessao tipo=exercicio nome="34d"'));
      expect(
        cubit.state,
        const DiagSessionState(kind: 'exercicio', name: '34d'),
      );
    });

    test('close encerra a sessão', () async {
      final cubit = DiagSessionCubit(kind: 'exercicio', name: '34d');

      await cubit.close();

      expect(sessoes(), contains('[sessao] fim: exercicio 34d'));
    });

    blocTest<DiagSessionCubit, DiagSessionState>(
      'trocar o nome encerra a sessão e abre outra',
      build: () => DiagSessionCubit(kind: 'exercicio', name: '34d'),
      act: (cubit) => cubit.trocar(kind: 'exercicio', name: '35a'),
      expect: () => [const DiagSessionState(kind: 'exercicio', name: '35a')],
      verify: (_) {
        expect(sessoes(), contains('[sessao] fim: exercicio 34d'));
        expect(sessoes(), contains('#sessao tipo=exercicio nome="35a"'));
      },
    );

    test('trocar sem mudança não abre nem encerra nada', () {
      final cubit = DiagSessionCubit(kind: 'exercicio', name: '34d');
      addTearDown(cubit.close);
      final antes = abertas();

      cubit.trocar(kind: 'exercicio', name: '34d');

      expect(abertas(), antes);
      expect(sessoes(), isNot(contains('[sessao] fim')));
      expect(cubit.state.name, '34d');
    });
  });
}
