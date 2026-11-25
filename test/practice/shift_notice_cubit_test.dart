// O aviso da faixa da partitura (BL14b, movido para o comum no BL33): mostrar e
// fechar, com o mesmo aviso que o detector devolve (os avisos iguais não emitem
// de novo).
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/shift_detector.dart';
import 'package:zywny_comum/practice/shift_notice_cubit.dart';

void main() {
  group('ShiftNoticeState', () {
    test('começa sem aviso e é igual pelo conteúdo do aviso', () {
      expect(const ShiftNoticeState().notice, isNull);
      expect(
        const ShiftNoticeState(notice: ShiftNotice('Toque mais agudo')),
        const ShiftNoticeState(notice: ShiftNotice('Toque mais agudo')),
      );
    });
  });

  group('ShiftNoticeCubit', () {
    const aviso = ShiftNotice('Ajuste o TRANSPOSE');

    blocTest<ShiftNoticeCubit, ShiftNoticeState>(
      'mostrar um aviso o guarda',
      build: ShiftNoticeCubit.new,
      act: (cubit) => cubit.show(aviso),
      expect: () => const [ShiftNoticeState(notice: aviso)],
    );

    blocTest<ShiftNoticeCubit, ShiftNoticeState>(
      'fechar zera o aviso',
      build: ShiftNoticeCubit.new,
      seed: () => const ShiftNoticeState(notice: aviso),
      act: (cubit) => cubit.clear(),
      expect: () => const [ShiftNoticeState()],
    );

    blocTest<ShiftNoticeCubit, ShiftNoticeState>(
      'o mesmo aviso de novo não emite',
      build: ShiftNoticeCubit.new,
      seed: () => const ShiftNoticeState(notice: aviso),
      act: (cubit) => cubit.show(const ShiftNotice('Ajuste o TRANSPOSE')),
      expect: () => const <ShiftNoticeState>[],
    );

    blocTest<ShiftNoticeCubit, ShiftNoticeState>(
      'fechar sem aviso não emite',
      build: ShiftNoticeCubit.new,
      act: (cubit) => cubit.clear(),
      expect: () => const <ShiftNoticeState>[],
    );
  });
}
