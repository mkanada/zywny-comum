// LP25 — A escada de repetição do compasso com erro (Dart puro, sem Flutter).
//
// Quando um compasso da passagem única erra, ele repete degrau a degrau: só
// notas (modo espera), depois cada andamento menor que o da etapa, até o da
// etapa. Errou em qualquer degrau, aviso e volta ao primeiro; acertou num degrau
// que não é o último, aviso de "acertou", contagem de um compasso e o degrau de
// cima; acertou no último, a música segue (o `PracticeController` faz a parte
// de tocar; aqui só está a ordem dos degraus).
//
// Os andamentos vêm de quem chama (o app passa `kMusicStageSpeeds`): este arquivo
// não tem número de andamento nenhum.
library;

import 'package:meta/meta.dart';

/// Um degrau da escada: só notas (modo espera) ou um andamento, como fração do
/// escrito (0,5 é metade).
@immutable
class RepeatRung {
  /// O degrau "só notas": modo espera, o aluno toca a parte dele com a música
  /// parada à espera.
  const RepeatRung.wait() : speed = null;

  /// Um andamento: [speed] é fração do escrito, maior que zero.
  const RepeatRung.tempo(double speed)
    : assert(speed > 0, 'o andamento de um degrau é maior que zero'),
      speed = speed;

  /// O andamento como fração do escrito; `null` no degrau "só notas".
  final double? speed;

  /// É o degrau "só notas".
  bool get isWait => speed == null;

  @override
  bool operator ==(Object other) => other is RepeatRung && other.speed == speed;

  @override
  int get hashCode => speed.hashCode;

  @override
  String toString() => isWait ? 'RepeatRung.wait' : 'RepeatRung($speed)';
}

/// O aviso que a tela mostra quando o degrau acaba.
enum RepeatNotice {
  /// Nenhum aviso: a escada acabou (a música segue) ou ainda não acabou um degrau.
  none,

  /// Errou o compasso: o aviso grande, e o compasso volta ao primeiro degrau.
  missed,

  /// Acertou num degrau que não é o último: o aviso "acertou", e o degrau de cima.
  passed,
}

/// O que vem depois do degrau que acabou.
@immutable
class RepeatOutcome {
  const RepeatOutcome({required this.notice, this.next, this.countIn = false});

  /// O aviso da tela.
  final RepeatNotice notice;

  /// O degrau em que o compasso toca agora; `null` quando a escada acabou e a
  /// música segue a partir do compasso seguinte.
  final RepeatRung? next;

  /// Antes do degrau [next], a contagem de um compasso (no andamento dele).
  final bool countIn;

  /// A escada acabou: a música segue.
  bool get finished => next == null;

  @override
  String toString() =>
      'RepeatOutcome(notice: $notice, next: $next, countIn: $countIn)';
}

/// O estado da escada para a tela: o compasso que repete, o degrau, o aviso que
/// está na tela (se há) e se a contagem de um compasso corre.
@immutable
class RepeatStatus {
  const RepeatStatus({
    required this.measure,
    required this.rung,
    required this.rungIndex,
    required this.rungCount,
    this.notice = RepeatNotice.none,
    this.countingIn = false,
  });

  /// O compasso (ocorrência de `ScoreTimeline.measures`) que repete.
  final int measure;

  /// O degrau em que o compasso está, ou o que vem a seguir quando há aviso.
  final RepeatRung rung;

  /// A posição do degrau (0 é o primeiro) e quantos degraus a escada tem.
  final int rungIndex;
  final int rungCount;

  /// O aviso na tela agora (`none` quando não há).
  final RepeatNotice notice;

  /// A contagem de um compasso corre antes deste degrau.
  final bool countingIn;
}

/// A escada de um compasso com erro: os degraus na ordem e o degrau atual.
class RepeatLadder {
  /// A escada [rungs], na ordem (o primeiro é o de volta depois de um erro).
  RepeatLadder(List<RepeatRung> rungs) : rungs = List.unmodifiable(rungs) {
    if (rungs.isEmpty) {
      throw ArgumentError.value(rungs, 'rungs', 'a escada não pode ser vazia');
    }
  }

  /// A escada de uma etapa cujo andamento é [top] (fração do escrito), com os
  /// andamentos menores [speeds] (`null` em [top] é a etapa só notas).
  ///
  /// Etapa só notas: `[só notas]`. Etapa de 75%, com `speeds` de
  /// `kMusicStageSpeeds`: `[só notas, 50%, 75%]`. Os andamentos de [speeds] que
  /// não são menores que [top] ficam de fora, e a ordem e as repetições não
  /// importam.
  factory RepeatLadder.of({
    required double? top,
    required List<double> speeds,
  }) {
    if (top == null) return RepeatLadder([const RepeatRung.wait()]);
    if (top <= 0) {
      throw ArgumentError.value(top, 'top', 'o andamento da etapa é positivo');
    }
    final below = speeds.where((s) => s > 0 && s < top).toSet().toList()
      ..sort();
    return RepeatLadder([
      const RepeatRung.wait(),
      for (final speed in below) RepeatRung.tempo(speed),
      RepeatRung.tempo(top),
    ]);
  }

  /// Os degraus, do primeiro (só notas) ao último (o andamento da etapa).
  final List<RepeatRung> rungs;

  int _index = 0;

  /// O degrau em que o compasso toca agora.
  RepeatRung get current => rungs[_index];

  /// A posição do degrau atual (0 é o primeiro).
  int get index => _index;

  /// Quantos degraus tem a escada.
  int get length => rungs.length;

  /// O compasso errou no degrau atual: o aviso e o primeiro degrau de volta.
  RepeatOutcome missed() {
    _index = 0;
    return RepeatOutcome(notice: RepeatNotice.missed, next: rungs.first);
  }

  /// O compasso saiu certo no degrau atual. Se não é o último, sobe um degrau
  /// (com aviso e contagem); se é, a escada acabou e a música segue.
  RepeatOutcome passed() {
    if (_index == rungs.length - 1) {
      return const RepeatOutcome(notice: RepeatNotice.none);
    }
    _index++;
    return RepeatOutcome(
      notice: RepeatNotice.passed,
      next: rungs[_index],
      countIn: true,
    );
  }
}
