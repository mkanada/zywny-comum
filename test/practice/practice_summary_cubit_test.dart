// O resumo do treino (T04): "Detalhes" abre e fecha a parte de baixo da folha.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/practice_tools.dart';

void main() {
  group('PracticeSummaryCubit', () {
    test('começa sem os detalhes', () {
      final cubit = PracticeSummaryCubit();
      addTearDown(cubit.close);

      expect(cubit.state.details, isFalse);
    });

    blocTest<PracticeSummaryCubit, PracticeSummaryState>(
      'alternarDetalhes abre e fecha os detalhes',
      build: PracticeSummaryCubit.new,
      act: (cubit) {
        cubit.alternarDetalhes();
        cubit.alternarDetalhes();
      },
      expect: () => [
        const PracticeSummaryState(details: true),
        const PracticeSummaryState(),
      ],
    );
  });
}
