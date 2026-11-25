// A faixa do aviso de TRANSPOSE (Q07) por dentro: copia o aviso, fecha no prazo,
// fecha na próxima nota (se o aviso pede) e tira a escuta ao fechar.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/practice/shift_banner.dart';
import 'package:zywny_comum/practice/shift_detector.dart';
import 'package:zywny_comum/practice/shift_notice_cubit.dart';
import 'package:zywny_midi/midi_input_service.dart';

// O aviso e as notas de cada teste: montados no `setUp` do grupo.
late ShiftNoticeCubit _notice;
late StreamController<PlayedNote> _notes;

PlayedNote _nota({bool on = true}) =>
    PlayedNote(pitch: 60, velocity: 80, channel: 0, on: on, atSeconds: 0);

ShiftBannerCubit _criar({Duration duration = const Duration(seconds: 8)}) =>
    ShiftBannerCubit(notice: _notice, notes: _notes.stream, duration: duration);

void main() {
  group('ShiftBannerCubit', () {
    setUp(() {
      _notice = ShiftNoticeCubit();
      _notes = StreamController<PlayedNote>.broadcast();
    });

    tearDown(() async {
      await _notice.close();
      await _notes.close();
    });

    _testesDoAviso();
    _testesDoFechar();
    _testesDaNota();
  });
}

void _testesDoAviso() {
  test('sem aviso, a faixa está fechada', () {
    final cubit = _criar();
    addTearDown(cubit.close);

    expect(cubit.state.shown, isNull);
  });

  test('um aviso que já está no notificador aparece de saída', () {
    _notice.show(const ShiftNotice('oi'));
    final cubit = _criar();
    addTearDown(cubit.close);

    expect(cubit.state.shown, const ShiftNotice('oi'));
  });

  test('um aviso novo abre a faixa; zerar o notificador fecha', () async {
    final cubit = _criar();
    addTearDown(cubit.close);

    _notice.show(const ShiftNotice('oi'));
    await pumpEventQueue();
    expect(cubit.state.shown, const ShiftNotice('oi'));
    _notice.clear();
    await pumpEventQueue();
    expect(cubit.state.shown, isNull);
  });
}

void _testesDoFechar() {
  test('fechar() zera o aviso para quem o ouve', () async {
    _notice.show(const ShiftNotice('oi'));
    final cubit = _criar();
    addTearDown(cubit.close);

    cubit.fechar();
    await pumpEventQueue();

    expect(_notice.state.notice, isNull);
    expect(cubit.state.shown, isNull);
  });

  test('some sozinha no prazo', () async {
    final cubit = _criar(duration: const Duration(milliseconds: 20));
    addTearDown(cubit.close);

    _notice.show(const ShiftNotice('oi'));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(cubit.state.shown, isNull);
    expect(_notice.state.notice, isNull);
  });
}

void _testesDaNota() {
  test('o aviso que pede some na próxima nota tocada', () async {
    final cubit = _criar();
    addTearDown(cubit.close);

    _notice.show(const ShiftNotice('oi'));
    await pumpEventQueue();
    _notes.add(_nota());
    await pumpEventQueue();
    await pumpEventQueue();

    expect(cubit.state.shown, isNull);
  });

  test('a nota que chega junto com o aviso não o fecha', () async {
    final cubit = _criar();
    addTearDown(cubit.close);

    _notes.add(_nota());
    _notice.show(const ShiftNotice('oi'));
    await pumpEventQueue();

    expect(cubit.state.shown, const ShiftNotice('oi'));
  });

  test('um aviso que não pede (hideOnPlay falso) não fecha na nota', () async {
    final cubit = _criar();
    addTearDown(cubit.close);

    _notice.show(const ShiftNotice('oi', hideOnPlay: false));
    await pumpEventQueue();
    _notes.add(_nota());
    await pumpEventQueue();

    expect(cubit.state.shown, const ShiftNotice('oi', hideOnPlay: false));
  });

  test('ao fechar, deixa de ouvir o notificador', () async {
    final cubit = _criar();
    await cubit.close();

    // Com a escuta ainda ligada, o aviso chegaria a um Cubit fechado e lançaria.
    expect(() => _notice.show(const ShiftNotice('oi')), returnsNormally);
    await pumpEventQueue();
    expect(cubit.isClosed, isTrue);
  });
}
