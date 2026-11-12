part of 'course_model.dart';

/// `play-chord`: as cifras da rodada, uma lista fixa ou um sorteio. O pacote
/// guarda o texto; quem monta o acorde é o app (EX02).
sealed class ChordsSpec {
  const ChordsSpec();
}

/// As cifras que o autor escreveu, na ordem.
class FixedChords extends ChordsSpec {
  const FixedChords(this.symbols);

  final List<String> symbols;
}

/// Um acorde por pergunta, com qualidade e raiz sorteadas. Com [sequence]
/// diferente de `random`, as raízes seguem a sequência a partir de [key] e
/// [roots] não vale; sem [roots], qualquer raiz (ou só as brancas com
/// [whiteOnly]).
class RandomChords extends ChordsSpec {
  const RandomChords({
    required this.qualities,
    required this.count,
    required this.sequence,
    this.roots,
    this.whiteOnly = false,
    this.key = 'C',
  });

  final List<String> qualities;
  final List<String>? roots;
  final bool whiteOnly;
  final int count;
  final String sequence;

  /// O tom de partida das sequências (e a escala do `diatonic`).
  final String key;
}

/// Os graus de [degrees] em cada um dos [count] tons, na ordem de [sequence]
/// a partir de [key]: um acorde por grau e por tom.
class DegreeChords extends ChordsSpec {
  const DegreeChords({
    required this.degrees,
    required this.count,
    required this.sequence,
    this.key = 'C',
  });

  final List<String> degrees;
  final int count;
  final String sequence;
  final String key;
}

/// `play-chord`: o aluno toca o acorde pedido no teclado MIDI, e o app
/// confere as notas e o que mais o exercício pedir (EX02).
class PlayChordSpec extends ExerciseSpec {
  const PlayChordSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.chords,
    required this.inversions,
    required this.hand,
    required this.split,
    required this.strict,
    required this.omit5,
    required this.prompt,
    this.voicing,
    this.range,
    this.voiceLeading,
    this.bpm,
    this.beats = 4,
  });

  @override
  ExerciseType get type => ExerciseType.playChord;

  final ChordsSpec chords;

  /// Uma por acorde, em ciclo; com um item só, vale para todos.
  final List<ChordInversionChoice> inversions;

  /// O nome do molde (`close`, `7-3`…); `null` não confere o molde.
  final String? voicing;

  final ChordHand hand;

  /// A nota que separa as mãos (`left` fica abaixo, `right` a partir dela).
  final Pitch split;

  /// A faixa em que o acorde pode soar; `null` é o teclado todo.
  final NoteRange? range;

  /// Com `true`, a inversão e o molde pedidos batem exatamente (e o molde não
  /// aceita nota dobrada).
  final bool strict;

  /// A 5ª justa pode faltar nos acordes de sétima ou mais.
  final bool omit5;

  final ChordPrompt prompt;

  /// Movimento máximo, em semitons, de um acorde para o seguinte; acima disso
  /// o acorde vale, mas conta como erro de primeira.
  final int? voiceLeading;

  /// Andamento do modo com tempo (EX03): cada pergunta dura [beats] tempos e
  /// o metrônomo marca. `null` = sem tempo (a pergunta espera o aluno).
  final int? bpm;

  /// Tempos por acorde, no modo com tempo.
  final int beats;
}

/// `show:` do `play-chart` (EX11): a grade mostra as cifras ou os graus.
enum ChartShow implements WireEnum {
  chords,
  degrees;

  @override
  String get wire => name;
}

/// O baixo da base (EX12): `none`, a fundamental no 1 (`root`), a fundamental
/// e a 5ª (`root-fifth`), a linha andante (`walking`) ou o baixo do estilo
/// (`pattern`).
enum BackingBass implements WireEnum {
  none,
  root,
  rootFifth,
  walking,
  pattern;

  @override
  String get wire => switch (this) {
    rootFifth => 'root-fifth',
    _ => name,
  };
}

/// A base gerada de um `play-chart` (EX12): o estilo (já resolvido: o do
/// molde de comping quando o exercício não diz), a bateria, o baixo, o volume
/// relativo ao piano (0 a 100) e os compassos de base antes da forma.
class BackingSpec {
  const BackingSpec({
    required this.style,
    required this.drums,
    required this.bass,
    required this.volume,
    required this.intro,
  });

  final BackingStyle style;
  final bool drums;
  final BackingBass bass;
  final int volume;

  /// Compassos de base antes da forma, no lugar da contagem.
  final int intro;
}

/// `play-chart` (EX11): uma grade de acordes tocada no andamento, com um
/// padrão rítmico aplicado a cada acorde. A grade vem como texto (`chart`) ou
/// da biblioteca (`progression`); o molde, da biblioteca ou escrito (`pattern`).
class PlayChartSpec extends ExerciseSpec {
  const PlayChartSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.key,
    required this.time,
    required this.pattern,
    required this.bpm,
    required this.choruses,
    required this.split,
    required this.strict,
    required this.omit5,
    required this.strictRhythm,
    required this.metronome,
    required this.show,
    required this.keyStart,
    this.chartText,
    this.progression,
    this.progressionBars,
    this.swing,
    this.voicing,
    this.keys,
    this.cycle,
    this.backing,
  }) : assert((chartText == null) != (progression == null));

  @override
  ExerciseType get type => ExerciseType.playChart;

  /// A grade escrita (o texto do EX09), ou `null` quando vem de [progression].
  final String? chartText;

  /// O nome da progressão da biblioteca (`I-IV-V-I`), ou `null`.
  final String? progression;

  /// Quantos compassos a progressão ocupa, ou `null` para o tamanho dela.
  final int? progressionBars;

  /// O tom e a fórmula da grade. Com `keys` ou `cycle`, é o tom escrito.
  final String key;
  final String time;

  /// O molde de comping (EX11): da biblioteca, ou escrito no exercício.
  final CompingPattern pattern;

  final int bpm;

  /// O swing, de 50 a 75; `null` é o do padrão (67 nos que nascem com swing).
  final int? swing;

  /// Quantas voltas da forma.
  final int choruses;

  /// O molde do acorde (`voicing:`, como no `play-chord`), ou `null`.
  final String? voicing;

  /// A nota que separa as mãos.
  final Pitch split;

  /// Com `true`, a inversão e o molde pedidos batem exatamente (D-EXE-ACORDE).
  final bool strict;

  /// A 5ª justa pode faltar nos acordes de sétima ou mais.
  final bool omit5;

  /// `true`: um ataque fora do padrão reprova (o `strict-rhythm`).
  final bool strictRhythm;

  /// O clique do metrônomo durante a forma.
  final bool metronome;

  final ChartShow show;

  /// `keys:` e `cycle:` (EX05): a grade é transposta em cada rodada.
  final KeyChoice? keys;
  final KeyCycle? cycle;
  final KeyStart keyStart;

  /// A base gerada (EX12), ou `null` para só o metrônomo.
  final BackingSpec? backing;
}

/// `listen-chord` (EX04): o zywny toca um acorde e o aluno diz a qualidade
/// (botões com o nome) ou, com `answer: function`, se ele é casa ou tensão.
/// Sem teclado MIDI.
class ListenChordSpec extends ExerciseSpec {
  const ListenChordSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.answer,
    required this.count,
    required this.play,
    required this.inversion,
    required this.key,
    this.qualities = const [],
    this.roots,
    this.degrees = const [],
  });

  @override
  ExerciseType get type => ExerciseType.listenChord;

  final ChordAnswerKind answer;

  /// Quantas perguntas. Com `roots` em lista, uma por nota, e este valor não
  /// vale (o leitor recusa o `count` junto).
  final int count;

  /// `quality`: as qualidades, na ordem dos botões. Vazio no `function`.
  final List<String> qualities;

  /// `quality`: a fundamental de cada pergunta, sorteada ou em lista. `null` no
  /// `function`.
  final NotesSpec? roots;

  /// `quality`: como o acorde soa.
  final ChordPlay play;

  /// `quality`: `root`, ou `random` (sorteada entre as inversões que a
  /// qualidade tem).
  final ChordInversionChoice inversion;

  /// `function`: o tom (`C`, `Am`…), ou `random` para sortear um por pergunta.
  final String key;

  /// `function`: os graus que podem soar. Vazio no `quality`.
  final List<String> degrees;
}

/// `listen-groove` (EX13): a pergunta toca dois compassos da base (EX12) num
/// dos grooves da lista, e o aluno diz qual é (botões com o nome). Sem teclado
/// MIDI, como o `listen-chord`.
class ListenGrooveSpec extends ExerciseSpec {
  const ListenGrooveSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.grooves,
    required this.count,
  });

  @override
  ExerciseType get type => ExerciseType.listenGroove;

  /// Os grooves que os botões mostram, na ordem do autor (dois ou mais).
  final List<ListenGroove> grooves;

  /// Quantas perguntas (1 a 40); cada uma sorteia um groove da lista.
  final int count;
}

/// `listen-progression` (EX15): o zywny toca o acorde da tônica, uma pausa e
/// uma progressão; o aluno diz qual é (`choice`) ou toca o baixo de cada acorde
/// (`bass`). Cada uma das [progressions] é a grade escrita (`I | vi | ii V | I`),
/// já com o nome da biblioteca trocado por ela.
class ListenProgressionSpec extends ExerciseSpec {
  const ListenProgressionSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.answer,
    required this.progressions,
    required this.key,
    required this.style,
    required this.bpm,
    required this.count,
  });

  @override
  ExerciseType get type => ExerciseType.listenProgression;

  final ProgressionAnswer answer;

  /// As progressões, como grades escritas (dois ou mais com `choice`). Os
  /// botões mostram os graus delas, na ordem do autor.
  final List<String> progressions;

  /// O tom (`C`, `Am`…), ou `random` para sortear um por pergunta.
  final String key;

  /// A base que soa com a progressão (EX12): `null` é o bloco (a mão direita
  /// em acordes e o baixo). Só estilos de compasso 4/4.
  final BackingStyle? style;

  /// O andamento, em semínimas por minuto (50 a 140).
  final int bpm;

  /// Quantas perguntas (1 a 40). Com `bass`, quantas progressões: cada acorde
  /// de uma progressão é uma nota a tocar.
  final int count;
}
