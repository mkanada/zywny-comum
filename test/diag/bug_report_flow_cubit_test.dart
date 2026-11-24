import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/diag/bug_report_flow_cubit.dart';

void main() {
  final captura = Uint8List.fromList([1, 2, 3]);

  group('BugReportFlowState', () {
    test('começa com a tela andando e sem relatório', () {
      const estado = BugReportFlowState();

      expect(estado.parada, isFalse);
      expect(estado.formulario, isFalse);
      expect(estado.captura, isNull);
    });

    test('é igual pelo valor (Equatable)', () {
      expect(
        const BugReportFlowState(parada: true),
        const BugReportFlowState(parada: true),
      );
      expect(
        const BugReportFlowState(parada: true),
        isNot(const BugReportFlowState()),
      );
    });
  });

  group('BugReportFlowCubit', () {
    blocTest<BugReportFlowCubit, BugReportFlowState>(
      'congelar para a tela de trás; chamar de novo não emite',
      build: BugReportFlowCubit.new,
      act: (cubit) {
        cubit.congelar();
        cubit.congelar();
      },
      expect: () => [const BugReportFlowState(parada: true)],
    );

    blocTest<BugReportFlowCubit, BugReportFlowState>(
      'mostrar abre o relatório com a captura, com a tela ainda parada',
      build: BugReportFlowCubit.new,
      act: (cubit) {
        cubit.congelar();
        cubit.mostrar(captura);
      },
      expect: () => [
        const BugReportFlowState(parada: true),
        BugReportFlowState(parada: true, formulario: true, captura: captura),
      ],
    );

    blocTest<BugReportFlowCubit, BugReportFlowState>(
      'mostrar sem captura (não deu para tirar) abre o relatório sem imagem',
      build: BugReportFlowCubit.new,
      act: (cubit) => cubit.mostrar(null),
      expect: () => [const BugReportFlowState(formulario: true)],
    );

    blocTest<BugReportFlowCubit, BugReportFlowState>(
      'fechar volta ao estado inicial e larga a captura',
      build: BugReportFlowCubit.new,
      act: (cubit) {
        cubit.congelar();
        cubit.mostrar(captura);
        cubit.fechar();
      },
      expect: () => [
        const BugReportFlowState(parada: true),
        BugReportFlowState(parada: true, formulario: true, captura: captura),
        const BugReportFlowState(),
      ],
    );
  });
}
