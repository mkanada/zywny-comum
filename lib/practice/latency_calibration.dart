// T04: calibração de latência de entrada+saída. O app toca [kCalibrationClicks]
// cliques a 100 bpm pelo `SoundEngine` ativo; o aluno aperta qualquer tecla
// junto de cada um. A latência é a mediana de (carimbo da tecla − instante
// agendado do clique), sem os 2 primeiros (o aluno ainda está pegando o
// pulso). Mede saída + reação + entrada de uma vez — a reação humana a um
// pulso regular tende a ~0 (antecipação), o método dos jogos de ritmo.
import 'dart:async';

import '../audio/sound_engine.dart';
import '../midi/midi_input_service.dart';

const int kCalibrationClicks = 8;
const int kCalibrationSkip = 2;

/// 100 bpm.
const double kCalibrationIntervalSeconds = 0.6;

/// Acima disto avisa ("fone Bluetooth?").
const double kCalibrationWarnMs = 80;

/// Uma tecla só conta para um clique se cair a até isto dele (segundos) —
/// metade do intervalo, senão seria ambígua.
const double _kMatchWindowSeconds = kCalibrationIntervalSeconds / 2;

/// Mediana de `tecla − clique` (ms), sem os [kCalibrationSkip] primeiros
/// cliques. Cada clique casa com a **primeira** tecla dentro da janela
/// (`clique − janela` … `clique + janela`); clique sem tecla é ignorado.
/// `null` se sobrar menos de 3 medidas (o aluno não acompanhou).
double? calibrationLatencyMs(
  List<double> clickSeconds,
  List<double> pressSeconds,
) {
  final offsets = <double>[];
  for (var i = kCalibrationSkip; i < clickSeconds.length; i++) {
    final click = clickSeconds[i];
    for (final p in pressSeconds) {
      if ((p - click).abs() <= _kMatchWindowSeconds) {
        offsets.add((p - click) * 1000);
        break;
      }
    }
  }
  if (offsets.length < 3) return null;
  offsets.sort();
  final mid = offsets.length ~/ 2;
  return offsets.length.isOdd
      ? offsets[mid]
      : (offsets[mid - 1] + offsets[mid]) / 2;
}

/// Uma rodada de calibração: agenda os cliques em [engine] e recolhe as
/// teclas de [input]. [result] sai quando o último clique passou (+ folga).
class LatencyCalibration {
  LatencyCalibration({required this.engine, required this.input});

  final SoundEngine engine;
  final MidiInputService input;

  final List<double> clickSeconds = [];
  final List<double> pressSeconds = [];
  StreamSubscription<PlayedNote>? _sub;
  final _done = Completer<double?>();

  /// Para a UI: quantos cliques já soaram.
  int get clicksPlayed {
    final now = engine.nowSeconds;
    return clickSeconds.where((c) => c <= now).length;
  }

  Future<double?> get result => _done.future;

  /// Começa 1 s à frente do mais cedo agendável (tempo de o aluno se
  /// preparar) e resolve [result] 0,6 s depois do último clique.
  void start() {
    final first = engine.earliestScheduleSeconds + 1.0;
    final midi = <ScheduledMidi>[];
    for (var i = 0; i < kCalibrationClicks; i++) {
      final at = first + i * kCalibrationIntervalSeconds;
      clickSeconds.add(at);
      final accent = i == 0;
      midi
        ..add(ScheduledMidi(at, 0x99, accent ? 76 : 77, 110))
        ..add(ScheduledMidi(at + 0.05, 0x89, accent ? 76 : 77, 0));
    }
    engine.schedule(midi);
    _sub = input.notes.listen((n) {
      if (n.on) pressSeconds.add(n.atSeconds);
    });
    final total = Duration(
      milliseconds:
          ((first - engine.nowSeconds) * 1000 +
                  kCalibrationClicks * kCalibrationIntervalSeconds * 1000 +
                  600)
              .round(),
    );
    Timer(total, finish);
  }

  /// Fecha a rodada agora (a UI pode cancelar) e resolve [result].
  void finish() {
    if (_done.isCompleted) return;
    unawaited(_sub?.cancel());
    _sub = null;
    _done.complete(calibrationLatencyMs(clickSeconds, pressSeconds));
  }

  void cancel() {
    engine.allNotesOff();
    finish();
  }
}
