import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/settings/color_picker_cubit.dart';

void main() {
  const azul = Color(0xFF1E88E5);
  const verde = Color(0xFF2E7D32);

  group('ColorPickerState', () {
    test('é igual pelo valor (Equatable)', () {
      final hsv = HSVColor.fromColor(azul);
      expect(
        ColorPickerState(color: azul, hsv: hsv),
        equals(ColorPickerState(color: azul, hsv: hsv)),
      );
      expect(
        ColorPickerState(color: azul, hsv: hsv),
        isNot(equals(ColorPickerState(color: azul, hsv: hsv, serial: 1))),
      );
    });

    test('copyWith troca só o campo pedido', () {
      final estado = ColorPickerState(
        color: azul,
        hsv: HSVColor.fromColor(azul),
      );

      expect(estado.copyWith(), estado);
      expect(estado.copyWith(serial: 4).serial, 4);
      expect(estado.copyWith(serial: 4).color, azul);
    });
  });

  group('ColorPickerCubit', () {
    test('começa com a cor opaca, o ajuste dela e serial zero', () {
      final cubit = ColorPickerCubit(initial: const Color(0x801E88E5));
      addTearDown(cubit.close);

      expect(cubit.state.color, azul);
      expect(cubit.state.hsv, HSVColor.fromColor(azul));
      expect(cubit.state.serial, 0);
    });

    blocTest<ColorPickerCubit, ColorPickerState>(
      'escolher põe a cor da paleta (opaca) e sobe o serial',
      build: () => ColorPickerCubit(initial: azul),
      act: (cubit) => cubit.escolher(const Color(0x802E7D32)),
      expect: () => [
        ColorPickerState(
          color: verde,
          hsv: HSVColor.fromColor(verde),
          serial: 1,
        ),
      ],
    );

    blocTest<ColorPickerCubit, ColorPickerState>(
      'escolher da cor que já está ainda emite (o serial sobe)',
      build: () => ColorPickerCubit(initial: azul),
      act: (cubit) {
        cubit.escolher(azul);
        cubit.escolher(azul);
      },
      expect: () => [
        ColorPickerState(color: azul, hsv: HSVColor.fromColor(azul), serial: 1),
        ColorPickerState(color: azul, hsv: HSVColor.fromColor(azul), serial: 2),
      ],
    );

    final ajuste = HSVColor.fromColor(azul).withHue(120);
    blocTest<ColorPickerCubit, ColorPickerState>(
      'ajustar põe a cor do ajuste e sobe o serial',
      build: () => ColorPickerCubit(initial: azul),
      act: (cubit) => cubit.ajustar(ajuste),
      expect: () => [
        ColorPickerState(color: ajuste.toColor(), hsv: ajuste, serial: 1),
      ],
    );

    blocTest<ColorPickerCubit, ColorPickerState>(
      'o código digitado com seis dígitos muda a cor e não sobe o serial',
      build: () => ColorPickerCubit(initial: azul),
      act: (cubit) => cubit.digitar('ad1457'),
      expect: () => [
        ColorPickerState(
          color: const Color(0xFFAD1457),
          hsv: HSVColor.fromColor(const Color(0xFFAD1457)),
        ),
      ],
    );

    blocTest<ColorPickerCubit, ColorPickerState>(
      'código incompleto ou que não é hexadecimal não muda nada',
      build: () => ColorPickerCubit(initial: azul),
      act: (cubit) {
        cubit.digitar('ad145');
        cubit.digitar('zzzzzz');
      },
      expect: () => <ColorPickerState>[],
    );
  });
}
