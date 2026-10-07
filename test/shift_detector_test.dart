// Q07 — Lembretes e detector de deslocamento: o teclado com o TRANSPOSE
// errado (esquecido de ontem, ou não ajustado hoje) é visto pelas notas
// erradas todas à mesma distância das esperadas; o app diz o que ajustar.
//
// A ligação com a tela (`main.dart`) não tem teste de widget — o
// `FlutterMidiInputService` não é injetável —, então a faixa é testada com o
// mesmo controlador de treino e o mesmo `ShiftBanner` que a tela usa.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/audio/score_audio_scheduler.dart';
import 'package:zywny/audio/sound_engine.dart';
import 'package:zywny/midi/midi_input_service.dart';
import 'package:zywny/music/performance_track.dart';
import 'package:zywny/music/pitch_frame.dart';
import 'package:zywny/practice/hand.dart';
import 'package:zywny/practice/practice_controller.dart';
import 'package:zywny/practice/shift_banner.dart';
import 'package:zywny/practice/shift_detector.dart';

class _Engine implements SoundEngine {
  double now = 0;
  final List<ScheduledMidi> scheduled = [];
  final List<List<int>> sent = [];

  @override
  double get nowSeconds => now;
  @override
  double get earliestScheduleSeconds => now + 0.02;
  @override
  double get outputLatencySeconds => 0.02;
  @override
  Future<void> start() async {}
  @override
  Future<void> loadSoundFont(Uint8List bytes) async {}
  @override
  void send(List<int> midi) => sent.add(midi);
  @override
  void schedule(List<ScheduledMidi> events) => scheduled.addAll(events);
  @override
  void clearScheduled() {}
  @override
  void allNotesOff() {}
  @override
  Future<void> dispose() async {}
}

class _Input implements MidiInputService {
  final StreamController<PlayedNote> _notes =
      StreamController<PlayedNote>.broadcast();
  final StreamController<int> _sustain = StreamController<int>.broadcast();
  final ValueNotifier<Set<int>> _held = ValueNotifier(const {});

  @override
  Stream<PlayedNote> get notes => _notes.stream;
  @override
  Stream<int> get sustain => _sustain.stream;
  @override
  ValueListenable<Set<int>> get held => _held;

  void note(int pitch, {required bool on, double atSeconds = 0}) => _notes.add(
    PlayedNote(
      pitch: pitch,
      velocity: on ? 80 : 0,
      channel: 0,
      on: on,
      atSeconds: atSeconds,
    ),
  );

  @override
  void dispose() {
    unawaited(_notes.close());
    unawaited(_sustain.close());
    _held.dispose();
  }
}

VsbDocument _doc() => VsbDocument.fromBytes(
  Uint8List.fromList(File('test/fixtures/erik-satie.vsb').readAsBytesSync()),
);

void _advanceUntil(_Engine engine, ScoreAudioScheduler scheduler, double ms) {
  var guard = 0;
  while (scheduler.positionMs < ms) {
    engine.now += 0.025;
    scheduler.pump();
    if (guard++ > 200000) throw StateError('não convergiu para $ms ms');
  }
}

/// Um treino de verdade sobre a partitura de teste, com o detector ligado.
class _Rig {
  _Rig({
    required this.mode,
    PitchFrame frame = PitchFrame.identity,
    ShiftDetector? detector,
  }) : frame = frame,
       detector = detector ?? ShiftDetector() {
    track = PerformanceTrack.fromDocument(_doc());
    scheduler = ScoreAudioScheduler(
      engine: engine,
      track: track,
      autoTick: false,
    );
    scoreController = ScoreController(document: _doc());
    practice = PracticeController(
      midiInput: midi,
      track: track,
      scheduler: scheduler,
      controller: scoreController,
      hand: Hand.direita,
      mode: mode,
      writtenFromReceived: frame.writtenFromReceived,
      shiftDetector: this.detector,
      onShift: (d) {
        shifts.add(d);
        onShift?.call(d);
      },
    );
    practice.start();
  }

  final PracticeMode mode;
  final PitchFrame frame;
  final ShiftDetector detector;
  final _Engine engine = _Engine();
  final _Input midi = _Input();
  late final PerformanceTrack track;
  late final ScoreAudioScheduler scheduler;
  late final ScoreController scoreController;
  late final PracticeController practice;
  final List<int> shifts = [];
  void Function(int d)? onShift;

  /// Os acordes que a mão do aluno toca, em ordem: (instante, alturas).
  List<({double onMs, List<int> pitches})> get chords {
    final byOnMs = <double, Set<int>>{};
    for (final e in track.events) {
      if (Hand.direita.studentStaves.contains(e.staff) && !e.ornament) {
        byOnMs.putIfAbsent(e.onMs, () => {}).add(e.pitch);
      }
    }
    final onsets = byOnMs.keys.toList()..sort();
    return [for (final t in onsets) (onMs: t, pitches: byOnMs[t]!.toList())];
  }

  /// Toca o [round]-ésimo acorde com o teclado deslocado de [shift] semitons
  /// (+3: cada tecla manda 3 a mais), todas as teclas juntas, e solta. No modo
  /// espera o acorde é o do passo de agora (o passo não anda com erro).
  Future<void> play(
    int round, {
    int shift = 0,
    Future<void> Function()? flush,
  }) async {
    flush ??= pumpEventQueue;
    final step = practice.currentStep.value;
    final chord = chords[round];
    final onMs = mode == PracticeMode.wait ? step!.onMs : chord.onMs;
    final pitches = mode == PracticeMode.wait
        ? step!.notes.map((e) => e.pitch).toSet().toList()
        : chord.pitches;
    _advanceUntil(engine, scheduler, onMs);
    for (final p in pitches) {
      midi.note(p + shift, on: true, atSeconds: engine.now);
    }
    await flush();
    for (final p in pitches) {
      midi.note(p + shift, on: false, atSeconds: engine.now);
    }
    await flush();
  }

  void dispose() {
    practice.dispose();
    scoreController.dispose();
    midi.dispose();
  }
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('ShiftDetector', () {
    // Um erro com uma esperada só: a distância é uma.
    int? w(ShiftDetector d, int? distance) =>
        d.wrong(distance == null ? const [] : [distance]);

    test('6 erros a +3 disparam, no sexto', () {
      final d = ShiftDetector();
      for (var i = 0; i < 5; i++) {
        expect(w(d, 3), isNull);
      }
      expect(w(d, 3), 3);
      expect(d.fired, isTrue);
    });

    test('vale o sinal: −2 dispara com −2', () {
      final d = ShiftDetector();
      for (var i = 0; i < 5; i++) {
        w(d, -2);
      }
      expect(w(d, -2), -2);
    });

    test('uma nota certa no meio zera a contagem', () {
      final d = ShiftDetector();
      for (var i = 0; i < 5; i++) {
        w(d, 3);
      }
      d.correct();
      expect(w(d, 3), isNull);
      for (var i = 0; i < 4; i++) {
        expect(w(d, 3), isNull);
      }
      expect(w(d, 3), 3);
    });

    test('erros espalhados não disparam', () {
      final d = ShiftDetector();
      for (final distance in [3, 4, 3, 2, 3, -3, 3, 5, 3, 1, 3, 7]) {
        expect(w(d, distance), isNull);
      }
      expect(d.fired, isFalse);
    });

    test('distância diferente recomeça a contagem', () {
      final d = ShiftDetector();
      for (var i = 0; i < 5; i++) {
        w(d, 3);
      }
      expect(w(d, 4), isNull);
      for (var i = 0; i < 4; i++) {
        expect(w(d, 4), isNull);
      }
      expect(w(d, 4), 4);
    });

    test('sem esperada por perto, distância 0 ou além de uma oitava zeram', () {
      for (final bad in [null, 0, 13, -13]) {
        final d = ShiftDetector();
        for (var i = 0; i < 5; i++) {
          w(d, 3);
        }
        expect(w(d, bad), isNull, reason: '$bad');
        expect(w(d, 3), isNull, reason: '$bad zerou');
      }
      final d = ShiftDetector();
      for (var i = 0; i < 5; i++) {
        w(d, 12);
      }
      expect(w(d, 12), 12, reason: 'uma oitava ainda vale');
    });

    test('acorde: o d que explica todos os erros, mesmo com a mais próxima '
        'mudando', () {
      // Si–Ré–Fá♯ (59, 62, 66) com o teclado em +3: chegam 65 e 69 (62 acerta).
      // 65 está a −1 de 66 e a +3 de 62; 69 está a +3 de 66.
      final d = ShiftDetector();
      final expected = [59, 62, 66];
      List<int> dist(int p) => [for (final e in expected) p - e];
      int? last;
      for (var i = 0; i < 3; i++) {
        last = d.wrong(dist(65));
        last = d.wrong(dist(69));
      }
      expect(last, 3);
    });

    test('acorde: erros sem um d em comum não disparam', () {
      final d = ShiftDetector();
      final expected = [59, 62, 66];
      List<int> dist(int p) => [for (final e in expected) p - e];
      for (final p in [60, 64, 70, 61, 65, 71, 63, 68]) {
        expect(d.wrong(dist(p)), isNull, reason: '$p');
      }
    });

    test('havendo mais de um d possível, o de menor módulo', () {
      final d = ShiftDetector(notes: 2);
      expect(d.wrong([3, -1]), isNull);
      expect(d.wrong([3, -1, 8]), -1);
    });

    test('dispara só uma vez', () {
      final d = ShiftDetector();
      for (var i = 0; i < 6; i++) {
        w(d, 3);
      }
      for (var i = 0; i < 20; i++) {
        expect(w(d, 3), isNull);
      }
    });

    test('rearm() volta a vigiar', () {
      final d = ShiftDetector();
      for (var i = 0; i < 6; i++) {
        w(d, 3);
      }
      d.rearm();
      for (var i = 0; i < 5; i++) {
        expect(w(d, 3), isNull);
      }
      expect(w(d, 3), 3);
    });

    test('desligado (enabled false) não conta nada', () {
      var on = false;
      final d = ShiftDetector(enabled: () => on);
      for (var i = 0; i < 20; i++) {
        expect(w(d, 3), isNull);
      }
      on = true;
      for (var i = 0; i < 5; i++) {
        expect(w(d, 3), isNull);
      }
      expect(w(d, 3), 3);
    });

    test('N é configurável', () {
      final d = ShiftDetector(notes: 2);
      expect(w(d, 1), isNull);
      expect(w(d, 1), 1);
    });
  });

  group('o texto do aviso', () {
    test('música sem transposição: o teclado está transposto em d', () {
      final n = shiftNoticeFor(d: 3, k: 0, frameShiftsOut: false);
      expect(
        n.message,
        'Parece que o teclado está transposto em +3. '
        'Ajuste o TRANSPOSE para 0.',
      );
      expect(
        shiftNoticeFor(d: -2, k: 0, frameShiftsOut: false).message,
        contains('−2'),
      );
      expect(n.hideOnPlay, isTrue);
    });

    test('música transposta, teclado conferido: valor pedido + d', () {
      // Pedido +3 (k = −3); o teclado está em +5: o casador vê d = +2.
      final n = shiftNoticeFor(d: 2, k: -3, frameShiftsOut: true);
      expect(n.message, 'Parece que o TRANSPOSE está em +5. Ajuste para +3.');
    });

    test('música transposta, teclado esquecido em 0', () {
      // Pedido +3, teclado em 0 (que transpõe): w = r + k → d = k = −3.
      final n = shiftNoticeFor(d: -3, k: -3, frameShiftsOut: true);
      expect(n.message, 'Parece que o TRANSPOSE está em 0. Ajuste para +3.');
    });

    test('música transposta, teclado não conferido: a distância é o valor', () {
      final n = shiftNoticeFor(d: 5, k: -3, frameShiftsOut: false);
      expect(n.message, 'Parece que o TRANSPOSE está em +5. Ajuste para +3.');
    });

    test('teclado não conferido que já estava certo: nada a avisar', () {
      // Pedido +3, o teclado já está em +3 e transpõe a saída; o app ainda
      // supunha que não (d = +3 = −k).
      expect(shiftIsAlreadyRight(d: 3, k: -3, frameShiftsOut: false), isTrue);
      expect(shiftIsAlreadyRight(d: 5, k: -3, frameShiftsOut: false), isFalse);
      expect(shiftIsAlreadyRight(d: 2, k: -3, frameShiftsOut: true), isFalse);
      expect(shiftIsAlreadyRight(d: 3, k: 0, frameShiftsOut: false), isFalse);
    });
  });

  group('lembrete de voltar a 0', () {
    bool remind({
      bool previous = true,
      bool now = false,
      bool keyboard = true,
      bool? out,
      bool appIsSound = false,
    }) => shouldRemindTransposeReset(
      previousWasTransposed: previous,
      nowTransposed: now,
      hasKeyboard: keyboard,
      keyboardShiftsOut: out,
      appIsSound: appIsSound,
    );

    test('só no caso do passo 3', () {
      expect(remind(), isTrue, reason: 'não conferido');
      expect(remind(out: false), isTrue);
      expect(remind(out: true), isFalse, reason: 'o detector vê de verdade');
      expect(remind(previous: false), isFalse, reason: 'anterior normal');
      expect(remind(now: true), isFalse, reason: 'esta é transposta');
      expect(remind(keyboard: false), isFalse, reason: 'sem teclado');
      expect(remind(appIsSound: true), isFalse, reason: 'som só do app');
    });
  });

  for (final mode in PracticeMode.values) {
    group('no treino, $mode', () {
      test('teclado em +3 numa música sem transposição: avisa em até 6 '
          'acordes', () async {
        final rig = _Rig(mode: mode);
        addTearDown(rig.dispose);
        for (var i = 0; i < 3; i++) {
          await rig.play(i, shift: 3);
        }
        expect(rig.shifts, [3], reason: 'o acorde dá 2 erros por vez');
        for (var i = 3; i < 8; i++) {
          await rig.play(i, shift: 3);
        }
        expect(rig.shifts, [3], reason: 'só uma vez');
      });

      test('um acorde certo no meio zera', () async {
        final rig = _Rig(mode: mode);
        addTearDown(rig.dispose);
        // 4 erros a +3, um acorde certo: a conta recomeça.
        await rig.play(0, shift: 3);
        await rig.play(1, shift: 3);
        await rig.play(2);
        expect(rig.shifts, isEmpty);
        // 3 erros (um acorde de 3 notas) e depois mais 3.
        await rig.play(3, shift: 3);
        expect(rig.shifts, isEmpty);
        await rig.play(4, shift: 3);
        expect(rig.shifts, [3]);
      });

      test('erros espalhados não disparam', () async {
        final rig = _Rig(mode: mode);
        addTearDown(rig.dispose);
        for (var i = 0; i < 8; i++) {
          await rig.play(i, shift: [1, 4, 2, -5, 6, -1, 5, 2][i]);
        }
        expect(rig.shifts, isEmpty);
      });

      test('teclado conferido que transpõe, esquecido em 0 (música em Dó)', () async {
        // Pedido +3 (k = −3): o teclado em 0 manda a escrita; o casador soma k.
        const frame = PitchFrame(-3, keyboardShiftsOut: true);
        final rig = _Rig(mode: mode, frame: frame);
        addTearDown(rig.dispose);
        for (var i = 0; i < 4; i++) {
          await rig.play(i);
        }
        expect(rig.shifts, [-3]);
        final notice = shiftNoticeFor(
          d: rig.shifts.single,
          k: -3,
          frameShiftsOut: true,
        );
        expect(notice.message, contains('está em 0'));
      });

      test('detector desligado (teclado que não transpõe) não avisa', () async {
        final rig = _Rig(
          mode: mode,
          detector: ShiftDetector(enabled: () => false),
        );
        addTearDown(rig.dispose);
        for (var i = 0; i < 6; i++) {
          await rig.play(i, shift: 3);
        }
        expect(rig.shifts, isEmpty);
      });
    });
  }

  group('a faixa', () {
    Future<void> show(
      WidgetTester tester,
      ValueNotifier<ShiftNotice?> notice,
      Stream<PlayedNote> notes,
    ) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [ShiftBanner(notice: notice, notes: notes)],
          ),
        ),
      ),
    );

    testWidgets('música sem transposição, teclado em +3: a faixa aparece em '
        'até 6 notas erradas', (tester) async {
      final notice = ValueNotifier<ShiftNotice?>(null);
      final rig = _Rig(mode: PracticeMode.wait);
      addTearDown(() {
        rig.dispose();
        notice.dispose();
      });
      rig.onShift = (d) =>
          notice.value = shiftNoticeFor(d: d, k: 0, frameShiftsOut: false);
      await show(tester, notice, rig.midi.notes);
      expect(find.byKey(const ValueKey('shift-banner')), findsNothing);
      for (var i = 0; i < 3; i++) {
        await rig.play(i, shift: 3, flush: tester.pump);
      }
      await tester.pump();
      expect(find.byKey(const ValueKey('shift-banner')), findsOneWidget);
      expect(
        find.text(
          'Parece que o teclado está transposto em +3. '
          'Ajuste o TRANSPOSE para 0.',
        ),
        findsOneWidget,
      );
      expect(rig.practice.report.wrong, 6, reason: "avisou no 6º erro");
      // As cores do treino animam; sem isto a árvore fecha com um ticker vivo.
      rig.practice.stop();
      rig.scoreController.clearAll();
      await tester.pump(const Duration(seconds: 1));
    });

    // O resto da faixa não precisa de treino: o aviso vem de um notificador
    // e as notas, de um teclado falso à parte.
    late ValueNotifier<ShiftNotice?> notice;
    late _Input keyboard;
    setUp(() {
      notice = ValueNotifier(null);
      keyboard = _Input();
    });
    tearDown(() {
      notice.dispose();
      keyboard.dispose();
    });

    testWidgets('some sozinha em 8 s', (tester) async {
      await show(tester, notice, keyboard.notes);
      notice.value = const ShiftNotice('oi');
      await tester.pump();
      expect(find.text('oi'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('oi'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1, milliseconds: 100));
      expect(find.text('oi'), findsNothing);
      expect(notice.value, isNull);
    });

    testWidgets('some ao tocar a próxima nota', (tester) async {
      await show(tester, notice, keyboard.notes);
      notice.value = const ShiftNotice('oi');
      await tester.pump();
      keyboard.note(60, on: false);
      await tester.pump();
      expect(find.text('oi'), findsOneWidget, reason: 'soltar não conta');
      keyboard.note(60, on: true);
      await tester.pump();
      await tester.pump();
      expect(find.text('oi'), findsNothing);
      expect(notice.value, isNull);
    });

    testWidgets('o lembrete de voltar a 0 não some ao tocar', (tester) async {
      await show(tester, notice, keyboard.notes);
      notice.value = const ShiftNotice(
        kShiftReminderMessage,
        hideOnPlay: false,
      );
      await tester.pump();
      keyboard.note(60, on: true);
      await tester.pump();
      await tester.pump();
      expect(find.text(kShiftReminderMessage), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(find.text(kShiftReminderMessage), findsNothing);
    });

    testWidgets('tocar na faixa a fecha', (tester) async {
      await show(tester, notice, keyboard.notes);
      notice.value = const ShiftNotice('oi');
      await tester.pump();
      await tester.tap(find.text('oi'));
      await tester.pump();
      expect(find.text('oi'), findsNothing);
      expect(notice.value, isNull);
    });

    testWidgets('um aviso novo reinicia os 8 s', (tester) async {
      await show(tester, notice, keyboard.notes);
      notice.value = const ShiftNotice('um');
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      notice.value = const ShiftNotice('dois');
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('dois'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('dois'), findsNothing);
    });
  });
}
