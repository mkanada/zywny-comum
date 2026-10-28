// EX07, item 2: as marcas de expressão que o `midi.json` não traz. Medido em
// 2026-10-28 com um MusicXML que tem p e f, um staccato e uma ligadura: a
// velocity fica 90 nas duas dinâmicas, a nota em staccato dura o valor inteiro
// e a ligadura não aparece em lugar nenhum do arquivo. Por isso as marcas
// vêm por outro caminho: quem gera a rodada (EX06, EX09) as põe aqui; as
// partituras de autor deixam [ExpressionMarks.empty] até o bridge exportar.

import 'package:meta/meta.dart';

/// Intensidade escrita, da mais fraca para a mais forte: a ordem do enum é a
/// ordem de intensidade (`index`).
enum DynamicLevel { pp, p, mp, mf, f, ff }

/// Uma dinâmica escrita, a partir de [atMs] (ms musicais) até a próxima.
@immutable
class DynamicMark {
  const DynamicMark({required this.atMs, required this.level});

  final double atMs;
  final DynamicLevel level;
}

/// Um crescendo ou diminuendo: do [startMs] ao [endMs] (ms musicais).
@immutable
class WedgeMark {
  const WedgeMark({
    required this.startMs,
    required this.endMs,
    required this.crescendo,
  });

  final double startMs;
  final double endMs;

  /// `true` para o crescendo, `false` para o diminuendo.
  final bool crescendo;
}

@immutable
class ExpressionMarks {
  const ExpressionMarks({
    this.dynamics = const [],
    this.wedges = const [],
    this.staccato = const {},
    this.accents = const {},
    this.slurs = const [],
  });

  /// Nenhuma marca: o que as partituras de autor têm até o bridge exportar.
  static const ExpressionMarks empty = ExpressionMarks();

  final List<DynamicMark> dynamics;
  final List<WedgeMark> wedges;

  /// Ids (de `SoundEvent.id`) das notas em staccato.
  final Set<String> staccato;

  /// Ids das notas acentuadas (o `<accent>` escrito, ou o molde do exercício).
  final Set<String> accents;

  /// Pares de ids ligados por ligadura de expressão: `(a, b)` com `b` logo
  /// depois de `a`, na mesma pauta.
  final List<(String, String)> slurs;
}
