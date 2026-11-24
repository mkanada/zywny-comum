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

/// Configurações **gerais** do app — valem para qualquer hino: som, saída,
/// metrônomo, cores, e o layout da partitura (tamanho da notação e as demais
/// opções do Verovio). O que é de um hino só — andamento, mão, trilha, tom —
/// fica em `PieceSettingsStore`.
///
/// Estado imutável do `SettingsCubit` (BL08, antes `AppSettings`). Cada valor
/// persistido é uma chave própria em `SharedPreferencesAsync` (ver
/// `settings_cubit.dart`); a tela recebe o estado pelo `BlocBuilder`.
class SettingsState extends Equatable {
  SettingsState({
    this.output = SoundOutput.appSynth,
    this.useScoreInstruments = false,
    this.soundOn = true,
    this.metronomeOn = false,
    this.practiceMode = PracticeMode.wait,
    // Verde, não o vermelho padrão do player: é também a cor da nota certa
    // no treino, e vermelho lá é a errada.
    this.highlightColor = kPracticeCorrectColor,
    this.practicePendingColor = kPracticePendingColor,
    this.practiceWrongColor = kPracticeWrongColor,
    this.studentPartColor = kPracticeStudentColor,
    this.haloWidth = 1.0,
    this.barColor = kDefaultBarColor,
    this.trailMeasures = kTrailDefaultMeasures,
    Set<TrailPhase>? trailPhases,
    List<TrailPhase>? trailPhaseOrder,
    Set<double>? trailSpeeds,
    this.rhythmToleranceMs = kDefaultRhythmToleranceMs,
    this.repeatNoticeSeconds = kDefaultRepeatNoticeSeconds,
    this.noteNaming = NoteNaming.latin,
    this.chordNotation = ChordNotation.brazilian,
    this.courseTextScale = 1.0,
    this.transposeByDefault = false,
    this.keyboardTranspose = const {},
    this.scoreLayout = const {},
    this.scorePageFitsBox = true,
    this.loaded = false,
  }) : trailPhases = trailPhases ?? {...TrailPhase.values},
       trailPhaseOrder = trailPhaseOrder ?? TrailPhase.values,
       trailSpeeds = trailSpeeds ?? {...kTrailSpeeds};

  /// `true` depois do primeiro `load` — antes disso valem os padrões.
  final bool loaded;

  final SoundOutput output;

  /// Program Change (M03): manda o instrumento da partitura ao teclado MIDI
  /// — desligado por padrão, o usuário quer o som do próprio piano.
  final bool useScoreInstruments;

  /// O som do app toca a partitura; desligado, o player só destaca as notas.
  /// Ligado por padrão (U04): o primeiro play de uma instalação nova soa.
  final bool soundOn;

  final bool metronomeOn;

  /// Espera ou tempo real — o tipo de treino que "Espera" arma.
  final PracticeMode practiceMode;

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

  /// Margem do tempo real em ms no andamento original (ver
  /// `PracticeController.rhythmToleranceMs`), entre
  /// [kMinRhythmToleranceMs] e [kMaxRhythmToleranceMs].
  final double rhythmToleranceMs;

  /// Quanto tempo o aviso da volta na hora fica na tela, em segundos, entre
  /// [kMinRepeatNoticeSeconds] e [kMaxRepeatNoticeSeconds].
  final double repeatNoticeSeconds;

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
    SoundOutput? output,
    bool? useScoreInstruments,
    bool? soundOn,
    bool? metronomeOn,
    PracticeMode? practiceMode,
    Color? highlightColor,
    Color? practicePendingColor,
    Color? practiceWrongColor,
    Color? studentPartColor,
    double? haloWidth,
    Color? barColor,
    int? trailMeasures,
    Set<TrailPhase>? trailPhases,
    List<TrailPhase>? trailPhaseOrder,
    Set<double>? trailSpeeds,
    double? rhythmToleranceMs,
    double? repeatNoticeSeconds,
    NoteNaming? noteNaming,
    ChordNotation? chordNotation,
    double? courseTextScale,
    bool? transposeByDefault,
    Map<String, KeyboardTransposeBehavior>? keyboardTranspose,
    Map<String, Object?>? scoreLayout,
    bool? scorePageFitsBox,
  }) => SettingsState(
    loaded: loaded ?? this.loaded,
    output: output ?? this.output,
    useScoreInstruments: useScoreInstruments ?? this.useScoreInstruments,
    soundOn: soundOn ?? this.soundOn,
    metronomeOn: metronomeOn ?? this.metronomeOn,
    practiceMode: practiceMode ?? this.practiceMode,
    highlightColor: highlightColor ?? this.highlightColor,
    practicePendingColor: practicePendingColor ?? this.practicePendingColor,
    practiceWrongColor: practiceWrongColor ?? this.practiceWrongColor,
    studentPartColor: studentPartColor ?? this.studentPartColor,
    haloWidth: haloWidth ?? this.haloWidth,
    barColor: barColor ?? this.barColor,
    trailMeasures: trailMeasures ?? this.trailMeasures,
    trailPhases: trailPhases ?? this.trailPhases,
    trailPhaseOrder: trailPhaseOrder ?? this.trailPhaseOrder,
    trailSpeeds: trailSpeeds ?? this.trailSpeeds,
    rhythmToleranceMs: rhythmToleranceMs ?? this.rhythmToleranceMs,
    repeatNoticeSeconds: repeatNoticeSeconds ?? this.repeatNoticeSeconds,
    noteNaming: noteNaming ?? this.noteNaming,
    chordNotation: chordNotation ?? this.chordNotation,
    courseTextScale: courseTextScale ?? this.courseTextScale,
    transposeByDefault: transposeByDefault ?? this.transposeByDefault,
    keyboardTranspose: keyboardTranspose ?? this.keyboardTranspose,
    scoreLayout: scoreLayout ?? this.scoreLayout,
    scorePageFitsBox: scorePageFitsBox ?? this.scorePageFitsBox,
  );

  @override
  List<Object?> get props => [
    loaded,
    output,
    useScoreInstruments,
    soundOn,
    metronomeOn,
    practiceMode,
    highlightColor,
    practicePendingColor,
    practiceWrongColor,
    studentPartColor,
    haloWidth,
    barColor,
    trailMeasures,
    trailPhases,
    trailPhaseOrder,
    trailSpeeds,
    rhythmToleranceMs,
    repeatNoticeSeconds,
    noteNaming,
    chordNotation,
    courseTextScale,
    transposeByDefault,
    keyboardTranspose,
    scoreLayout,
    scorePageFitsBox,
  ];
}
