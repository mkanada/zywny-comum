part of 'course_model.dart';

/// `mode:` do `harmonize` (EX16). `reharmonize` está no formato, mas ainda não
/// roda: a rearmonização (nível 6) fica para depois, e o leitor a recusa.
enum HarmonizeMode implements WireEnum {
  degrees('degrees'),
  play('play'),
  byEar('by-ear'),
  reharmonize('reharmonize');

  const HarmonizeMode(this.wire);

  @override
  final String wire;
}

/// `change:` do `harmonize` (EX16): onde o acorde pode trocar.
enum HarmonizeChange implements WireEnum {
  bar('bar'),
  halfBar('half-bar'),
  marked('marked');

  const HarmonizeChange(this.wire);

  @override
  final String wire;
}

/// `melody:` do `harmonize` (EX16): de onde vem a melodia.
sealed class MelodySource {
  const MelodySource();
}

/// `{step, key}`: uma melodia gerada pela leitura à primeira vista (só a mão
/// direita). Sem [key], o tom é o do passo.
class StepMelody extends MelodySource {
  const StepMelody({required this.step, this.key});

  /// O passo da leitura (`1a` a `100d`).
  final String step;

  /// O tom (`G`, `Am`…), ou `null` para o do passo.
  final String? key;
}

/// `{file}`: um `.musicxml` do autor, de domínio público, na pasta do curso.
class FileMelody extends MelodySource {
  const FileMelody(this.path);

  /// O caminho na pasta do curso.
  final String path;
}

/// `harmonize` (EX16): a melodia e os acordes que cabem nela. Os modos são
/// `degrees` (escolher o grau de cada trecho), `play` (tocar a melodia e os
/// acordes) e `by-ear` (ouvir a melodia e tocar só os acordes).
class HarmonizeSpec extends ExerciseSpec {
  const HarmonizeSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.mode,
    required this.melody,
    required this.chords,
    required this.change,
    required this.bpm,
    required this.split,
    required this.count,
    this.pattern,
  });

  @override
  ExerciseType get type => ExerciseType.harmonize;

  final HarmonizeMode mode;
  final MelodySource melody;

  /// Os graus permitidos (`I`, `IV`, `V7`…), na ordem do autor.
  final List<String> chords;

  final HarmonizeChange change;

  /// O molde do EX11 (com `play` e `by-ear`), ou `null` nos outros modos.
  final String? pattern;

  /// O andamento, em semínimas por minuto.
  final int bpm;

  /// A altura que separa as mãos: abaixo é a esquerda (os acordes).
  final Pitch split;

  /// Quantas melodias (só com `step`).
  final int count;
}

/// `style:` do `play-lead-sheet` (EX17): as regras de estilo, no lugar do molde.
/// Os de [LeadStyle.implemented] rodam; os outros estão no formato, e o leitor
/// os recusa com "ainda não roda" (como o `reharmonize` do EX16).
enum LeadStyle implements WireEnum {
  sevenThreeUnderMelody('7-3-under-melody'),
  blockUnderMelody('block-under-melody'),
  offBeatFill('off-beat-fill'),
  ballad('ballad'),
  balladRawlins('ballad-rawlins'),
  budPowell('bud-powell'),
  latinComping('latin-comping'),
  lockedHands('locked-hands'),
  drop2Melody('drop-2-melody'),
  stride('stride');

  const LeadStyle(this.wire);

  @override
  final String wire;

  /// Os estilos que o app já confere (EX17). Os outros esperam o passo que os
  /// traz (ver o `EX17`, "Notas de execução").
  static const implemented = {
    LeadStyle.sevenThreeUnderMelody,
    LeadStyle.blockUnderMelody,
    LeadStyle.offBeatFill,
    LeadStyle.ballad,
    LeadStyle.stride,
  };
}

/// `melody:` do `play-lead-sheet` (EX17): `check` confere a melodia nota a nota;
/// `free` só os acordes contam (a melodia pode ser enfeitada).
enum LeadMelody implements WireEnum {
  check('check'),
  free('free');

  const LeadMelody(this.wire);

  @override
  final String wire;
}

/// `play-lead-sheet` (EX17): a melodia escrita, com as cifras em cima. O aluno
/// toca a melodia na direita e o acorde na esquerda (ou embaixo da melodia, na
/// direita, nos estilos que pedem). [file] é o `.musicxml` do autor.
class PlayLeadSheetSpec extends ExerciseSpec {
  const PlayLeadSheetSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.file,
    required this.pattern,
    required this.melody,
    required this.bpm,
    required this.split,
    this.style,
    this.swing,
  });

  @override
  ExerciseType get type => ExerciseType.playLeadSheet;

  /// O caminho do `.musicxml` na pasta do curso (com as cifras).
  final String file;

  /// O molde da mão esquerda (EX11), pelo nome: `block` (o padrão), `any` ou um
  /// da biblioteca. Sem [style].
  final String pattern;

  /// O estilo, no lugar do molde, ou `null`.
  final LeadStyle? style;

  final LeadMelody melody;

  /// O andamento, em semínimas por minuto.
  final int bpm;

  /// O swing de 50 a 75 (só no que o app toca: as cifras da esquerda); `null` é
  /// o reto (50).
  final int? swing;

  /// A altura que separa as mãos: abaixo é a esquerda (os acordes).
  final Pitch split;
}

/// `target:` do `target-notes` (EX18): a nota que o aluno toca no tempo forte.
/// `chord-tone` é qualquer nota do acorde; `guide-tone` é a 3ª ou a 7ª mais
/// perto da nota tocada antes (a linha de guide tones).
enum TargetNote implements WireEnum {
  one('1'),
  three('3'),
  five('5'),
  seven('7'),
  nine('9'),
  chordTone('chord-tone'),
  guideTone('guide-tone');

  const TargetNote(this.wire);

  @override
  final String wire;
}

/// `when:` do `target-notes` (EX18): em que tempos cai o alvo. `bar` é o tempo 1
/// de cada compasso; `half-bar`, os tempos 1 e 3 (Rawlins 8); `change`, cada
/// troca de acorde.
enum TargetWhen implements WireEnum {
  bar('bar'),
  halfBar('half-bar'),
  change('change');

  const TargetWhen(this.wire);

  @override
  final String wire;
}

/// `between:` do `target-notes` (EX18): o que o aluno toca entre os alvos.
enum TargetBetween implements WireEnum {
  rest('rest'),
  free('free'),
  source('source'),
  enclosure('enclosure'),
  arpeggio3579('arpeggio-3579');

  const TargetBetween(this.wire);

  @override
  final String wire;
}

/// `source:` do `target-notes` (EX18), com `between: source` ou `free`: de onde
/// saem as notas entre os alvos.
enum TargetSource implements WireEnum {
  keyScale('key-scale'),
  blues('blues'),
  byChord('by-chord');

  const TargetSource(this.wire);

  @override
  final String wire;
}

/// `target-notes` (EX18): sobre a grade e a base, o aluno toca a nota-alvo em
/// cada tempo forte que [when] pede, e o que houver entre os alvos segue
/// [between]. [left] é `none` (a base faz o baixo), `root` ou o nome de um
/// molde de voicing (`shell-17`, `7-3`…), na esquerda, por troca de acorde.
class TargetNotesSpec extends ExerciseSpec {
  const TargetNotesSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.key,
    required this.time,
    required this.bpm,
    required this.target,
    required this.when,
    required this.between,
    required this.source,
    required this.left,
    required this.registerFrom,
    required this.registerTo,
    required this.split,
    required this.keyStart,
    this.chartText,
    this.progression,
    this.progressionBars,
    this.swing,
    this.keys,
    this.cycle,
    this.backing,
  }) : assert((chartText == null) != (progression == null));

  @override
  ExerciseType get type => ExerciseType.targetNotes;

  /// A grade escrita (o texto do EX09), ou `null` quando vem de [progression].
  final String? chartText;

  /// O nome da progressão da biblioteca, ou `null`.
  final String? progression;

  /// Quantos compassos a progressão ocupa, ou `null` para o tamanho dela.
  final int? progressionBars;

  /// O tom e a fórmula da grade (o tom escrito, com `keys` ou `cycle`).
  final String key;
  final String time;

  /// O andamento, em semínimas por minuto.
  final int bpm;

  /// O swing, de 50 a 75; `null` é o reto (50).
  final int? swing;

  final TargetNote target;
  final TargetWhen when;
  final TargetBetween between;

  /// A fonte das notas entre os alvos (com `between: source` ou `free`).
  final TargetSource source;

  /// `none`, `root` ou o nome de um molde de voicing (`kVoicingShapes`).
  final String left;

  /// A faixa da mão direita: as notas fora dela não contam.
  final Pitch registerFrom;
  final Pitch registerTo;

  /// A altura que separa as mãos: abaixo é a esquerda (D-EXE-MAOS).
  final Pitch split;

  /// `keys:`, `cycle:` e `key-start:` (EX05): a grade é transposta em cada rodada.
  final KeyChoice? keys;
  final KeyCycle? cycle;
  final KeyStart keyStart;

  /// A base gerada (EX12), ou `null` para só o metrônomo.
  final BackingSpec? backing;
}

/// `mode:` do `follow-form` (EX20): como o aluno acompanha a forma. `where`,
/// `enter` e `cues` rodam; os outros três estão no formato e o leitor os recusa
/// até o passe que os traz.
enum FollowMode implements WireEnum {
  where('where'),
  enter('enter'),
  cues('cues'),
  introOutro('intro-outro'),
  breakBars('break'),
  trading('trading');

  const FollowMode(this.wire);

  @override
  final String wire;
}

/// Os sinais do `cues` (EX20): o que o aluno deve tocar depois do sinal. Cada
/// um aparece um compasso antes da mudança.
enum FormSignal implements WireEnum {
  again('again'),
  next('next'),
  backToA('back-to-A'),
  bridge('bridge'),
  tag('tag'),
  end('end');

  const FormSignal(this.wire);

  @override
  final String wire;
}

/// `intro:` do `intro-outro` (EX20). Recusado pelo leitor até o passe do modo.
enum FormIntro implements WireEnum {
  turnaround4('turnaround-4'),
  last8('last-8'),
  dominantPedal('dominant-pedal'),
  latinVamp('latin-vamp');

  const FormIntro(this.wire);

  @override
  final String wire;
}

/// `ending:` do `intro-outro` (EX20). Recusado pelo leitor até o passe do modo.
enum FormEnding implements WireEnum {
  tag('tag'),
  tagMinorThird('tag-minor-third'),
  stop('stop');

  const FormEnding(this.wire);

  @override
  final String wire;
}

/// `enter:` do `follow-form` no modo `enter` (EX20): os compassos (ou a seção)
/// em que o aluno entra, e o padrão do que ele toca ali.
@immutable
class FollowEnter {
  const FollowEnter({required this.pattern, this.bars, this.section})
    : assert((bars == null) != (section == null));

  /// Os compassos da volta, contando do 1 (`11-12`), ou `null` com [section].
  final MeasureRange? bars;

  /// O nome da seção (`B`), ou `null` com [bars].
  final String? section;

  /// O molde que o aluno toca nos compassos de entrada (`block`…).
  final CompingPattern pattern;
}

/// `follow-form` (EX20): acompanhar a forma de uma grade, com a base gerada. A
/// grade vem como em `play-chart` (texto ou progressão); o que o aluno faz
/// depende de [mode]. As chaves que valem só num modo ficam nulas nos outros.
class FollowFormSpec extends ExerciseSpec {
  const FollowFormSpec({
    required super.id,
    required super.title,
    required super.pass,
    required super.line,
    required this.mode,
    required this.key,
    required this.time,
    required this.bpm,
    required this.choruses,
    required this.split,
    required this.questions,
    required this.answerWindow,
    required this.cues,
    required this.keyStart,
    this.chartText,
    this.progression,
    this.progressionBars,
    this.swing,
    this.enter,
    this.pattern,
    this.keys,
    this.cycle,
    this.backing,
  }) : assert((chartText == null) != (progression == null));

  @override
  ExerciseType get type => ExerciseType.followForm;

  final FollowMode mode;

  /// A grade escrita (o texto do EX09), ou `null` quando vem de [progression].
  final String? chartText;

  /// O nome da progressão da biblioteca, ou `null`.
  final String? progression;

  /// Quantos compassos a progressão ocupa, ou `null` para o tamanho dela.
  final int? progressionBars;

  /// O tom e a fórmula da grade (o tom escrito, com `keys` ou `cycle`).
  final String key;
  final String time;

  /// O andamento, em semínimas por minuto.
  final int bpm;

  /// O swing, de 50 a 75; `null` é o reto (50).
  final int? swing;

  /// Quantas voltas da forma (com `where`, `enter`, `break` e `trading`).
  final int choruses;

  /// A altura que separa as mãos (D-EXE-MAOS).
  final Pitch split;

  /// `where`: quantas perguntas na forma, e quantos tempos o aluno tem para
  /// responder cada uma.
  final int questions;
  final int answerWindow;

  /// `cues`: os sinais possíveis, na forma em que o autor os pôs.
  final List<FormSignal> cues;

  /// `enter`: os compassos (ou a seção) de entrada e o padrão do que se toca.
  final FollowEnter? enter;

  /// `cues`: o molde de comping que o aluno segue, como no `play-chart`.
  final CompingPattern? pattern;

  /// `keys:`, `cycle:` e `key-start:` (EX05): a grade é transposta em cada rodada.
  final KeyChoice? keys;
  final KeyCycle? cycle;
  final KeyStart keyStart;

  /// A base gerada (EX12), ou `null` para só o metrônomo.
  final BackingSpec? backing;
}
