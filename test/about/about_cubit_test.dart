import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/about/about_cubit.dart';

void main() {
  group('AboutState', () {
    test('copyWith troca só o campo pedido', () {
      const estado = AboutState(version: 'Versão 1.0.3 (4)');

      expect(estado.copyWith(), estado);
      expect(estado.copyWith(version: 'Versão 2.0.0').version, 'Versão 2.0.0');
    });

    test('é igual pelo valor (Equatable)', () {
      expect(
        const AboutState(version: 'x'),
        equals(const AboutState(version: 'x')),
      );
      expect(
        const AboutState(version: 'x'),
        isNot(equals(const AboutState(version: 'y'))),
      );
    });
  });

  group('AboutCubit', () {
    test('começa sem versão', () {
      final cubit = AboutCubit(loadVersion: () async => 'Versão 1.0.3 (4)');
      addTearDown(cubit.close);

      expect(cubit.state, const AboutState());
      expect(cubit.state.version, '');
    });

    blocTest<AboutCubit, AboutState>(
      'load emite a versão lida',
      build: () => AboutCubit(loadVersion: () async => 'Versão 1.0.3 (4)'),
      act: (cubit) => cubit.load(),
      expect: () => [const AboutState(version: 'Versão 1.0.3 (4)')],
    );

    test('se a tela fechar antes da versão chegar, não emite nem lança', () async {
      final versao = Completer<String>();
      final cubit = AboutCubit(loadVersion: () => versao.future);

      final carga = cubit.load();
      await cubit.close();
      versao.complete('Versão 1.0.3 (4)');

      await expectLater(carga, completes);
      expect(cubit.isClosed, isTrue);
      expect(cubit.state.version, '', reason: 'o estado não mudou depois do close');
    });
  });
}
