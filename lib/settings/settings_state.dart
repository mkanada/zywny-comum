import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:score_bridge/score_bridge.dart' show kDefaultBarColor;
import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_music/chord.dart' show ChordNotation;
import 'package:zywny_music/note_names.dart' show NoteNaming;

import '../practice/practice_colors.dart'
    show
        kPracticeCorrectColor,
        kPracticePendingColor,
        kPracticeStudentColor,
        kPracticeWrongColor;
import '../practice/practice_mode.dart'
    show PracticeMode, kDefaultRhythmToleranceMs;
import '../trail/trail_stage.dart'
    show TrailPhase, kTrailDefaultMeasures, kTrailSpeeds;

/// Limites da margem do tempo real nas configurações.
const double kMinRhythmToleranceMs = 30;
const double kMaxRhythmToleranceMs = 200;

/// Quanto tempo o aviso "Errou"/"Acertou" da volta na hora fica na tela, em
/// segundos (o padrão é o `kRepeatNoticeDuration`: 2 s; 0 não mostra aviso).
const double kMinRepeatNoticeSeconds = 0;
const double kMaxRepeatNoticeSeconds = 6;
const double kDefaultRepeatNoticeSeconds = 2;

/// Limites do tamanho do texto dos cursos (o "Aa" da lição).
const double kMinCourseTextScale = 0.85;
const double kMaxCourseTextScale = 2.0;

/// Como o TRANSPOSE de um teclado mexe no MIDI (fase Q, docs/plano/Q00, "O
/// problema do MIDI do teclado"). Não dá para saber pelo nome do aparelho: a
/// conferência (Q06) descobre e guarda por teclado. `null` = ainda não
/// conferido; quem usa supõe `false` enquanto isso.
@immutable
class KeyboardTransposeBehavior {
  const KeyboardTransposeBehavior({this.shiftsOut, this.shiftsIn});

  static const unknown = KeyboardTransposeBehavior();

  /// A conferência (Q06) já descobriu se o teclado transpõe a saída. Quem
  /// ainda não foi conferido não abre a folha de novo depois que a pessoa
  /// respondeu.
  bool get isChecked => shiftsOut != null;

  /// O teclado transpõe também o MIDI que **manda** (a recebida é a soada).
  final bool? shiftsOut;

  /// O teclado transpõe também o MIDI que **recebe** do app (M03).
  final bool? shiftsIn;

  @override
  bool operator ==(Object other) =>
      other is KeyboardTransposeBehavior &&
      other.shiftsOut == shiftsOut &&
      other.shiftsIn == shiftsIn;

  @override
  int get hashCode => Object.hash(shiftsOut, shiftsIn);

  @override
  String toString() =>
      'KeyboardTransposeBehavior(out=$shiftsOut, in=$shiftsIn)';
}

/// Saída de som (K03/M03): o sintetizador do app (`.sf2`) ou o teclado MIDI
/// conectado, tocando no som próprio do piano digital do usuário.
enum SoundOutput { appSynth, midiKeyboard }

/// Som e saída (K03, M03, U04): o que toca, em que saída, e o metrônomo.
class SoundSettings extends Equatable {
  const SoundSettings({
    this.output = SoundOutput.appSynth,
    this.useScoreInstruments = false,
    this.soundOn = true,
    this.metronomeOn = false,
  });

  final SoundOutput output;

  /// Program Change (M03): manda o instrumento da partitura ao teclado MIDI
  /// — desligado por padrão, o usuário quer o som do próprio piano.
  final bool useScoreInstruments;

  /// O som do app toca a partitura; desligado, o player só destaca as notas.
  /// Ligado por padrão (U04): o primeiro play de uma instalação nova soa.
  final bool soundOn;

  final bool metronomeOn;

  SoundSettings copyWith({
    SoundOutput? output,
    bool? useScoreInstruments,
    bool? soundOn,
    bool? metronomeOn,
  }) => SoundSettings(
    output: output ?? this.output,
    useScoreInstruments: useScoreInstruments ?? this.useScoreInstruments,
    soundOn: soundOn ?? this.soundOn,
    metronomeOn: metronomeOn ?? this.metronomeOn,
  );

  @override
  List<Object?> get props => [
    output,
    useScoreInstruments,
    soundOn,
    metronomeOn,
  ];
}

/// Espera e tempo real: o tipo de treino, a margem do ritmo e o aviso da volta.
class PracticeSettings extends Equatable {
  const PracticeSettings({
    this.practiceMode = PracticeMode.wait,
    this.rhythmToleranceMs = kDefaultRhythmToleranceMs,
    this.repeatNoticeSeconds = kDefaultRepeatNoticeSeconds,
  });

  /// Espera ou tempo real — o tipo de treino que "Espera" arma.
  final PracticeMode practiceMode;

  /// Margem do tempo real em ms no andamento original (ver
  /// `PracticeCubit.rhythmToleranceMs`), entre
  /// [kMinRhythmToleranceMs] e [kMaxRhythmToleranceMs].
  final double rhythmToleranceMs;

  /// Quanto tempo o aviso da volta na hora fica na tela, em segundos, entre
  /// [kMinRepeatNoticeSeconds] e [kMaxRepeatNoticeSeconds].
  final double repeatNoticeSeconds;

  PracticeSettings copyWith({
    PracticeMode? practiceMode,
    double? rhythmToleranceMs,
    double? repeatNoticeSeconds,
  }) => PracticeSettings(
    practiceMode: practiceMode ?? this.practiceMode,
    rhythmToleranceMs: rhythmToleranceMs ?? this.rhythmToleranceMs,
    repeatNoticeSeconds: repeatNoticeSeconds ?? this.repeatNoticeSeconds,
  );

  @override
  List<Object?> get props => [
    practiceMode,
    rhythmToleranceMs,
    repeatNoticeSeconds,
  ];
}

/// Cores e brilho: as da nota destacada, do treino, da parte do aluno e da
/// haste da virada.
class ColorSettings extends Equatable {
  const ColorSettings({
    // Verde, não o vermelho padrão do player: é também a cor da nota certa
    // no treino, e vermelho lá é a errada.
    this.highlightColor = kPracticeCorrectColor,
    this.practicePendingColor = kPracticePendingColor,
    this.practiceWrongColor = kPracticeWrongColor,
    this.studentPartColor = kPracticeStudentColor,
    this.haloWidth = 1.0,
    this.barColor = kDefaultBarColor,
  });

  /// Cor da nota destacada durante a execução — e, no treino, da nota que
  /// o aluno tocou certa.
  final Color highlightColor;

  /// Treino: cor da nota que o app está esperando o aluno tocar.
  final Color practicePendingColor;

  /// Treino: cor do pulso na nota esperada quando o aluno toca a tecla
  /// errada.
  final Color practiceWrongColor;

  /// Leitura pela música: cor da parte do aluno (as notas dele e o aviso
  /// "você"). Padrão: teal (`kPracticeStudentColor`).
  final Color studentPartColor;

  /// Multiplicador do raio do halo da nota destacada; `0` desliga.
  final double haloWidth;

  /// Cor da haste que varre a página na virada.
  final Color barColor;

  ColorSettings copyWith({
    Color? highlightColor,
    Color? practicePendingColor,
    Color? practiceWrongColor,
    Color? studentPartColor,
    double? haloWidth,
    Color? barColor,
  }) => ColorSettings(
    highlightColor: highlightColor ?? this.highlightColor,
    practicePendingColor: practicePendingColor ?? this.practicePendingColor,
    practiceWrongColor: practiceWrongColor ?? this.practiceWrongColor,
    studentPartColor: studentPartColor ?? this.studentPartColor,
    haloWidth: haloWidth ?? this.haloWidth,
    barColor: barColor ?? this.barColor,
  );

  @override
  List<Object?> get props => [
    highlightColor,
    practicePendingColor,
    practiceWrongColor,
    studentPartColor,
    haloWidth,
    barColor,
  ];
}

/// A trilha: o tamanho do trecho, as etapas (e a ordem) e os andamentos.
class TrailSettings extends Equatable {
  TrailSettings({
    this.trailMeasures = kTrailDefaultMeasures,
    Set<TrailPhase>? trailPhases,
    List<TrailPhase>? trailPhaseOrder,
    Set<double>? trailSpeeds,
  }) : trailPhases = trailPhases ?? {...TrailPhase.values},
       trailPhaseOrder = trailPhaseOrder ?? TrailPhase.values,
       trailSpeeds = trailSpeeds ?? {...kTrailSpeeds};

  /// Compassos lógicos por trecho da trilha (J03): padrão 5, mínimo 3.
  final int trailMeasures;

  /// Etapas que entram na trilha de cada trecho (padrão: todas). Nunca
  /// vazio — tirar a última é ignorado.
  final Set<TrailPhase> trailPhases;

  /// Ordem das etapas em cada trecho (todas, marcadas ou não).
  final List<TrailPhase> trailPhaseOrder;

  /// Andamentos (de `kTrailSpeeds`) das etapas no ritmo dos trechos
  /// (padrão: todos). Nunca vazio.
  final Set<double> trailSpeeds;

  TrailSettings copyWith({
    int? trailMeasures,
    Set<TrailPhase>? trailPhases,
    List<TrailPhase>? trailPhaseOrder,
    Set<double>? trailSpeeds,
  }) => TrailSettings(
    trailMeasures: trailMeasures ?? this.trailMeasures,
    trailPhases: trailPhases ?? this.trailPhases,
    trailPhaseOrder: trailPhaseOrder ?? this.trailPhaseOrder,
    trailSpeeds: trailSpeeds ?? this.trailSpeeds,
  );

  @override
  List<Object?> get props => [
    trailMeasures,
    trailPhases,
    trailPhaseOrder,
    trailSpeeds,
  ];
}

/// A notação e o texto: os nomes das notas, a cifra e o tamanho do texto dos
/// cursos.
class NotationSettings extends Equatable {
  const NotationSettings({
    this.noteNaming = NoteNaming.latin,
    this.chordNotation = ChordNotation.brazilian,
    this.courseTextScale = 1.0,
  });

  /// Nomes das notas na tela (I05, D-LIC-NOMES): `latin` (Dó–Ré–Mi, padrão)
  /// ou `letters` (C–D–E). O arquivo do curso usa sempre `C4`.
  final NoteNaming noteNaming;

  /// Como a cifra é escrita nas perguntas de acordes (EX03, D-EXE-CIFRA):
  /// `brazilian` (`C7M`, `Cm7(b5)`, o padrão) ou `american` (`Cmaj7`,
  /// `Cm7b5`). Um curso que fixa a sua (`chord-notation:`) não segue isto.
  final ChordNotation chordNotation;

  /// Multiplicador do texto nas telas dos cursos (lista, curso, lição,
  /// exercício), por cima do tamanho de fonte do sistema; entre
  /// [kMinCourseTextScale] e [kMaxCourseTextScale].
  final double courseTextScale;

  NotationSettings copyWith({
    NoteNaming? noteNaming,
    ChordNotation? chordNotation,
    double? courseTextScale,
  }) => NotationSettings(
    noteNaming: noteNaming ?? this.noteNaming,
    chordNotation: chordNotation ?? this.chordNotation,
    courseTextScale: courseTextScale ?? this.courseTextScale,
  );

  @override
  List<Object?> get props => [noteNaming, chordNotation, courseTextScale];
}

/// A partitura e a transposição: a transposição padrão, o que se sabe de cada
/// teclado, o layout que a pessoa mudou e a página que acompanha a caixa.
class ScoreSettings extends Equatable {
  const ScoreSettings({
    this.transposeByDefault = false,
    this.keyboardTranspose = const {},
    this.scoreLayout = const {},
    this.scorePageFitsBox = true,
  });

  /// "Abrir as músicas já sem acidentes" (fase Q): as que não têm escolha
  /// própria (`PieceSettings.transpose`) abrem transpostas para a armadura
  /// vazia. Desligado por padrão.
  final bool transposeByDefault;

  /// O que se sabe do TRANSPOSE de cada teclado, pelo nome do dispositivo MIDI
  /// (fase Q, Q06 preenche). Teclado não conferido: [KeyboardTransposeBehavior.unknown].
  final Map<String, KeyboardTransposeBehavior> keyboardTranspose;

  /// As opções do Verovio que a pessoa mudou, para todos os hinos. O que não
  /// está aqui segue o padrão do aparelho: o tamanho da notação no celular não
  /// é o do tablet. Os valores vêm como foram gravados: quem os usa passa por
  /// `layoutOverridesFrom` (lib/render/layout_options.dart), que descarta o
  /// que não serve mais.
  final Map<String, Object?> scoreLayout;

  /// A página acompanha a área da partitura (padrão) ou usa `pageWidth` e
  /// `pageHeight`. Vale para todos os hinos.
  final bool scorePageFitsBox;

  ScoreSettings copyWith({
    bool? transposeByDefault,
    Map<String, KeyboardTransposeBehavior>? keyboardTranspose,
    Map<String, Object?>? scoreLayout,
    bool? scorePageFitsBox,
  }) => ScoreSettings(
    transposeByDefault: transposeByDefault ?? this.transposeByDefault,
    keyboardTranspose: keyboardTranspose ?? this.keyboardTranspose,
    scoreLayout: scoreLayout ?? this.scoreLayout,
    scorePageFitsBox: scorePageFitsBox ?? this.scorePageFitsBox,
  );

  @override
  List<Object?> get props => [
    transposeByDefault,
    keyboardTranspose,
    scoreLayout,
    scorePageFitsBox,
  ];
}

/// Configurações **gerais** do app — valem para qualquer hino: som, saída,
/// metrônomo, cores, e o layout da partitura (tamanho da notação e as demais
/// opções do Verovio). O que é de um hino só — andamento, mão, trilha, tom —
/// fica em `PieceSettingsStore`.
///
/// Estado imutável do `SettingsCubit` (BL08, antes `AppSettings`). Cada valor
/// persistido é uma chave própria em `SharedPreferencesAsync` (ver
/// `settings_cubit.dart`); a tela recebe o estado pelo `BlocBuilder`.
///
/// O estado tem um sub-estado por assunto ([sound], [practice], [colors],
/// [trail], [notation], [score]). Os getters com os nomes de antes (`soundOn`,
/// `studentPartColor`…) continuam valendo e leem o sub-estado.
class SettingsState extends Equatable {
  SettingsState({
    this.loaded = false,
    SoundSettings? sound,
    PracticeSettings? practice,
    ColorSettings? colors,
    TrailSettings? trail,
    NotationSettings? notation,
    ScoreSettings? score,
  }) : sound = sound ?? const SoundSettings(),
       practice = practice ?? const PracticeSettings(),
       colors = colors ?? const ColorSettings(),
       trail = trail ?? TrailSettings(),
       notation = notation ?? const NotationSettings(),
       score = score ?? const ScoreSettings();

  /// `true` depois do primeiro `load` — antes disso valem os padrões.
  final bool loaded;

  final SoundSettings sound;
  final PracticeSettings practice;
  final ColorSettings colors;
  final TrailSettings trail;
  final NotationSettings notation;
  final ScoreSettings score;

  SoundOutput get output => sound.output;
  bool get useScoreInstruments => sound.useScoreInstruments;
  bool get soundOn => sound.soundOn;
  bool get metronomeOn => sound.metronomeOn;

  PracticeMode get practiceMode => practice.practiceMode;
  double get rhythmToleranceMs => practice.rhythmToleranceMs;
  double get repeatNoticeSeconds => practice.repeatNoticeSeconds;

  Color get highlightColor => colors.highlightColor;
  Color get practicePendingColor => colors.practicePendingColor;
  Color get practiceWrongColor => colors.practiceWrongColor;
  Color get studentPartColor => colors.studentPartColor;
  double get haloWidth => colors.haloWidth;
  Color get barColor => colors.barColor;

  int get trailMeasures => trail.trailMeasures;
  Set<TrailPhase> get trailPhases => trail.trailPhases;
  List<TrailPhase> get trailPhaseOrder => trail.trailPhaseOrder;
  Set<double> get trailSpeeds => trail.trailSpeeds;

  NoteNaming get noteNaming => notation.noteNaming;
  ChordNotation get chordNotation => notation.chordNotation;
  double get courseTextScale => notation.courseTextScale;

  bool get transposeByDefault => score.transposeByDefault;
  Map<String, KeyboardTransposeBehavior> get keyboardTranspose =>
      score.keyboardTranspose;
  Map<String, Object?> get scoreLayout => score.scoreLayout;
  bool get scorePageFitsBox => score.scorePageFitsBox;

  /// As etapas que entram na trilha, na ordem escolhida.
  List<TrailPhase> get trailPlanPhases => [
    for (final p in trailPhaseOrder)
      if (trailPhases.contains(p)) p,
  ];

  /// O que se sabe do TRANSPOSE de [deviceName] (`unknown` se não conferido).
  KeyboardTransposeBehavior keyboardTransposeOf(String? deviceName) =>
      keyboardTranspose[deviceName] ?? KeyboardTransposeBehavior.unknown;

  /// As configurações que mexem no que o aluno vê e ouve, para o relatório
  /// de bug e o log (cores em hexadecimal).
  Map<String, Object?> diagSnapshot() {
    String hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
    return {
      'saida': output.name,
      'somLigado': soundOn,
      'instrumentosDaPartitura': useScoreInstruments,
      'metronomo': metronomeOn,
      'modoDeTreino': practiceMode.name,
      'corDestaque': hex(highlightColor),
      'corPendente': hex(practicePendingColor),
      'corErro': hex(practiceWrongColor),
      'corAluno': hex(studentPartColor),
      'brilho': haloWidth,
      'corDaHaste': hex(barColor),
      'margemDoRitmoMs': rhythmToleranceMs,
      'avisoDaVoltaS': repeatNoticeSeconds,
      'nomeDasNotas': noteNaming.name,
      'cifra': chordNotation.name,
      'escalaDoTexto': courseTextScale,
      'transporPorPadrao': transposeByDefault,
      'layoutDaPartitura': scoreLayout,
      'paginaCabeNaCaixa': scorePageFitsBox,
    };
  }

  SettingsState copyWith({
    bool? loaded,
    SoundSettings? sound,
    PracticeSettings? practice,
    ColorSettings? colors,
    TrailSettings? trail,
    NotationSettings? notation,
    ScoreSettings? score,
  }) => SettingsState(
    loaded: loaded ?? this.loaded,
    sound: sound ?? this.sound,
    practice: practice ?? this.practice,
    colors: colors ?? this.colors,
    trail: trail ?? this.trail,
    notation: notation ?? this.notation,
    score: score ?? this.score,
  );

  @override
  List<Object?> get props => [
    loaded,
    sound,
    practice,
    colors,
    trail,
    notation,
    score,
  ];
}
