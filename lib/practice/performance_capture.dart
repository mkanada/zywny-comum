// EX07: a gravação da execução. Tudo o que o teclado manda (a hora e a força
// de cada tecla, o pedal) fica aqui em ms musicais. Quem converte a hora é
// quem chama (o PracticeController): a gravação não conhece relógio. Dart
// puro, sem UI; os medidores (meters.dart) leem esta estrutura.

import 'package:flutter/foundation.dart';
import 'package:zywny_audio/performance_track.dart';

/// Uma tecla apertada, do ataque ao fim. [offMs] é `null` enquanto ela está
/// segurada (ou se o teclado nunca mandou o fim).
@immutable
class CapturedNote {
  const CapturedNote({
    required this.pitch,
    required this.velocity,
    required this.onMs,
    this.offMs,
  });

  /// Altura **escrita**: a mesma que a conferência compara.
  final int pitch;
  final int velocity;
  final double onMs;
  final double? offMs;

  @override
  String toString() =>
      'CapturedNote($pitch vel=$velocity ${onMs.toStringAsFixed(1)}ms → '
      '${offMs == null ? '…' : '${offMs!.toStringAsFixed(1)}ms'})';
}

/// Um movimento do pedal de sustain. [down] vale para CC64 de 64 para cima.
@immutable
class CapturedPedal {
  const CapturedPedal({required this.atMs, required this.down});

  final double atMs;
  final bool down;
}

/// Uma nota escrita casada com a tocada: o que a conferência deu como certo
/// ou fora do tempo (EX07, item 2). Perdida e errada não têm par.
@immutable
class MatchedNote {
  const MatchedNote({required this.written, required this.played});

  final SoundEvent written;
  final CapturedNote played;
}

class PerformanceCapture {
  final List<CapturedNote> _notes = [];
  final List<CapturedPedal> _pedals = [];

  /// Índice, em [_notes], da tecla de cada altura que ainda está apertada.
  final Map<int, int> _held = {};

  /// Tecla apertada. Devolve o índice dela para [noteAt]: o casamento guarda o
  /// índice porque o fim da nota só chega depois, e a cópia já teria saído sem
  /// ele. Uma altura apertada de novo sem o fim anterior fica com o fim em
  /// aberto (o teclado não mandou o off).
  int noteOn(int pitch, int velocity, double atMs) {
    _notes.add(CapturedNote(pitch: pitch, velocity: velocity, onMs: atMs));
    final index = _notes.length - 1;
    _held[pitch] = index;
    return index;
  }

  /// Tecla solta. Sem ataque gravado para a altura (ela já estava apertada
  /// antes da gravação), não faz nada.
  void noteOff(int pitch, double atMs) {
    final index = _held.remove(pitch);
    if (index == null) return;
    final on = _notes[index];
    _notes[index] = CapturedNote(
      pitch: on.pitch,
      velocity: on.velocity,
      onMs: on.onMs,
      offMs: atMs,
    );
  }

  /// CC64 com o valor cru, 0..127.
  void pedal(int value, double atMs) {
    _pedals.add(CapturedPedal(atMs: atMs, down: value >= 64));
  }

  /// A nota de [index] (o que [noteOn] devolveu), já com o fim se ele chegou.
  CapturedNote noteAt(int index) => _notes[index];

  /// Todas as notas, em ordem de ataque.
  List<CapturedNote> get notes =>
      [..._notes]..sort((a, b) => a.onMs.compareTo(b.onMs));

  /// Todos os movimentos do pedal, em ordem de tempo.
  List<CapturedPedal> get pedals =>
      [..._pedals]..sort((a, b) => a.atMs.compareTo(b.atMs));

  void clear() {
    _notes.clear();
    _pedals.clear();
    _held.clear();
  }
}
