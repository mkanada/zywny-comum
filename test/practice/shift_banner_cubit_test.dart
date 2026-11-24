// A faixa do aviso de TRANSPOSE (Q07) por dentro: copia o aviso, fecha no prazo,
// fecha na próxima nota (se o aviso pede) e tira o ouvinte ao fechar.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/shift_banner.dart';
import 'package:zywny_comum/practice/shift_detector.dart';
import 'package:zywny_midi/midi_input_service.dart';

void main() {
  group('ShiftBannerCubit', () {
    late ValueNotifier<ShiftNotice?> notice;
    late StreamController<PlayedNote> notes;

    setUp(() {
      notice = ValueNotifier(null);
      notes = StreamController<PlayedNote>.broadcast();
    });

    tearDown(() async {
      notice.dispose();
      await notes.close();
    });

    PlayedNote nota({bool on = true}) =>
        PlayedNote(pitch: 60, velocity: 80, channel: 0, on: on, atSeconds: 0);

    ShiftBannerCubit criar({Duration duration = const Duration(seconds: 8)}) =>
        ShiftBannerCubit(
          notice: notice,
          onFechar: () => notice.value = null,
          notes: notes.stream,
          duration: duration,
        );

    test('sem aviso, a faixa está fechada', () {
      final cubit = criar();
      addTearDown(cubit.close);

      expect(cubit.state.shown, isNull);
    });

    test('um aviso que já está no notificador aparece de saída', () {
      notice.value = const ShiftNotice('oi');
      final cubit = criar();
      addTearDown(cubit.close);

      expect(cubit.state.shown, const ShiftNotice('oi'));
    });

    test('um aviso novo abre a faixa; zerar o notificador fecha', () {
      final cubit = criar();
      addTearDown(cubit.close);

      notice.value = const ShiftNotice('oi');
      expect(cubit.state.shown, const ShiftNotice('oi'));
      notice.value = null;
      expect(cubit.state.shown, isNull);
    });

    test('fechar() zera o aviso para quem o ouve', () {
      notice.value = const ShiftNotice('oi');
      final cubit = criar();
      addTearDown(cubit.close);

      cubit.fechar();

      expect(notice.value, isNull);
      expect(cubit.state.shown, isNull);
    });

    test('some sozinha no prazo', () async {
      final cubit = criar(duration: const Duration(milliseconds: 20));
      addTearDown(cubit.close);

      notice.value = const ShiftNotice('oi');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(cubit.state.shown, isNull);
      expect(notice.value, isNull);
    });

    test('o aviso que pede some na próxima nota tocada', () async {
      final cubit = criar();
      addTearDown(cubit.close);

      notice.value = const ShiftNotice('oi');
      await pumpEventQueue();
      notes.add(nota());
      await pumpEventQueue();

      expect(cubit.state.shown, isNull);
    });

    test('a nota que chega junto com o aviso não o fecha', () async {
      final cubit = criar();
      addTearDown(cubit.close);

      notes.add(nota());
      notice.value = const ShiftNotice('oi');
      await pumpEventQueue();

      expect(cubit.state.shown, const ShiftNotice('oi'));
    });

    test(
      'um aviso que não pede (hideOnPlay falso) não fecha na nota',
      () async {
        final cubit = criar();
        addTearDown(cubit.close);

        notice.value = const ShiftNotice('oi', hideOnPlay: false);
        await pumpEventQueue();
        notes.add(nota());
        await pumpEventQueue();

        expect(cubit.state.shown, const ShiftNotice('oi', hideOnPlay: false));
      },
    );

    test('ao fechar, deixa de ouvir o notificador', () async {
      final cubit = criar();
      await cubit.close();

      // Com o ouvinte ainda ligado, o aviso chegaria a um Cubit fechado e lançaria.
      expect(() => notice.value = const ShiftNotice('oi'), returnsNormally);
    });
  });
}
