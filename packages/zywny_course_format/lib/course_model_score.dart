part of 'course_model.dart';

/// `keys:` do `play-score` (EX05): os tons em que a partitura toca, rodada a
/// rodada. Ausente, a partitura toca no tom escrito.
sealed class KeyChoice {
  const KeyChoice();
}

/// `keys: [C, G, F]`: os tons na ordem escrita; a rodada N usa o N-ésimo.
class FixedKeys extends KeyChoice {
  const FixedKeys(this.keys);

  final List<String> keys;
}

/// `keys: all`: os 12 tons, em ordem sorteada uma vez por sessão.
class AllKeys extends KeyChoice {
  const AllKeys();
}

/// `keys: random`: um tom sorteado a cada rodada.
class RandomKeys extends KeyChoice {
  const RandomKeys();
}

/// `cycle:` do `play-score` (EX05): a rodada N usa o N-ésimo tom do ciclo, a
/// partir do tom escrito (`5ths` desce em quintas, como o `cycle-5` do EX01).
enum KeyCycle implements WireEnum {
  fifths('5ths'),
  fourths('4ths'),
  chromatic('chromatic'),
  wholeTone('whole-tone');

  const KeyCycle(this.wire);

  @override
  final String wire;
}

/// `key-start:` (EX05): o ciclo ou a lista começa no tom escrito, ou num tom
/// diferente a cada dia (`rotate`, Pike 7).
enum KeyStart implements WireEnum {
  written,
  rotate;

  @override
  String get wire => name;
}

class PlayScoreSpec extends ExerciseSpec {
  const PlayScoreSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.source,
    required this.hand,
    required this.mode,
    this.bpm,
    this.measures,
    this.keys,
    this.cycle,
    this.keyStart = KeyStart.written,
    this.practice,
    this.curtain = false,
    this.transpose = 0,
    this.student = const [],
  });

  @override
  ExerciseType get type => ExerciseType.playScore;

  final ScoreSource source;
  final HandChoice hand;
  final PlayMode mode;
  final int? bpm;
  final MeasureRange? measures;

  /// `keys:` (EX05), ou `null` para o tom escrito. Não vale junto com [cycle].
  final KeyChoice? keys;

  /// `cycle:` (EX05), ou `null`. Não vale junto com [keys].
  final KeyCycle? cycle;

  /// `key-start:` (EX05): só vale com [keys] ou [cycle].
  final KeyStart keyStart;

  /// `practice: cumulative` (EX22), ou `null` para a passagem toda.
  final PracticeChoice? practice;

  /// `curtain: true` (EX22): os compassos já tocados somem da partitura, e o
  /// seguinte só aparece no último tempo do atual. Só em `mode: realtime`.
  final bool curtain;

  /// `transpose:` (T18): semitons que levam a partitura ao tom da rodada; 0
  /// toca no tom escrito. Não vale junto com [keys] nem [cycle].
  final int transpose;

  /// `student:` (T18): os trechos que o aluno toca, cada um os `xml:id` das
  /// notas em ordem; o app toca o resto e não o cobra. Vazio: o aluno toca
  /// tudo (o de sempre). Os ids são os do Verovio com `xmlIdSeed: 1`.
  final List<List<String>> student;
}

class ChoiceSpec extends ExerciseSpec {
  const ChoiceSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.question,
    required this.options,
    required this.answer,
    this.image,
    this.abc,
  });

  @override
  ExerciseType get type => ExerciseType.choice;

  final String question;
  final List<String> options;

  /// Índice (base 0) da resposta certa em [options].
  final int answer;
  final String? image;
  final String? abc;
}

class ListenNoteSpec extends ExerciseSpec {
  const ListenNoteSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.notes,
    required this.input,
    required this.octave,
    required this.choices,
    this.reference,
    this.key,
  });

  @override
  ExerciseType get type => ExerciseType.listenNote;

  final NotesSpec notes;

  /// Nota tocada antes de cada pergunta (`null` = sem referência).
  final Pitch? reference;

  final AnswerInput input;

  /// Só vale com [AnswerInput.keyboard].
  final OctaveRule octave;

  /// Letras dos botões (`C`…`B`); só vale com [AnswerInput.buttons].
  final List<String> choices;

  /// Tom do sorteio; só vale com [AnswerInput.keyboard].
  final String? key;
}

/// `listen-interval`: toca dois sons (melódico ou harmônico) e o aluno escolhe
/// o nome do intervalo num botão.
class ListenIntervalSpec extends ExerciseSpec {
  const ListenIntervalSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.notes,
    required this.intervals,
    required this.direction,
    required this.play,
  });

  @override
  ExerciseType get type => ExerciseType.listenInterval;

  /// Notas de partida: a primeira de cada par.
  final NotesSpec notes;

  /// Os botões, na ordem do arquivo.
  final List<IntervalName> intervals;

  final IntervalDirection direction;

  final IntervalPlay play;
}

/// `listen-score`: mostra uma partitura gerada por um passo do treino de
/// leitura, toca uma versão com uma diferença e o aluno diz onde. O pacote
/// não conhece os passos: [step] é só o nome (`1a` a `100d`), e quem confere
/// e monta a partitura é o app.
class ListenScoreSpec extends ExerciseSpec {
  const ListenScoreSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.step,
    required this.change,
    required this.answer,
    required this.count,
    required this.bpm,
  });

  @override
  ExerciseType get type => ExerciseType.listenScore;

  /// O nome do passo do treino de leitura, como `4c`.
  final String step;

  final ScoreChange change;

  final ScoreAnswer answer;

  /// Quantas perguntas (partituras novas) a rodada tem.
  final int count;

  /// Andamento da frase; `null` usa o do passo.
  final int? bpm;
}
