import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:score_bridge/score_bridge.dart' show kDefaultBarColor;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zywny_diag/diag_log.dart';
import 'package:zywny_music/chord.dart' show ChordNotation;
import 'package:zywny_music/note_names.dart' show NoteNaming;

import '../practice/practice_colors.dart'
    show kPracticeCorrectColor, kPracticePendingColor, kPracticeWrongColor;
import '../practice/practice_mode.dart'
    show PracticeMode, kDefaultRhythmToleranceMs;
import '../trail/trail_stage.dart'
    show TrailPhase, kTrailDefaultMeasures, kTrailMinMeasures, kTrailSpeeds;

/// Limites da margem do tempo real nas configurações.
const double kMinRhythmToleranceMs = 30;
const double kMaxRhythmToleranceMs = 200;

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
/// Cada valor é uma chave própria em [SharedPreferencesAsync], que no
/// Android/Linux/Windows sobrevive a fechar o app e a instalar uma versão
/// nova por cima. Uma chave ausente ou ilegível vale o padrão, então uma
/// versão futura pode acrescentar ou abandonar chaves sem migração.
///
/// Avisa quem escuta a cada mudança; a tela de partitura aplica o que mudou
/// (trocar o motor de saída, a cor do destaque…) e os painéis se redesenham.
class AppSettings extends ChangeNotifier {
  AppSettings({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  // `sound_output` e `sound_use_score_instruments` já existiam antes desta
  // classe (M03): os nomes ficam, para quem já tinha escolhido.
  static const _kOutput = 'sound_output';
  static const _kUseScoreInstruments = 'sound_use_score_instruments';
  static const _kSoundOn = 'sound_on';
  static const _kMetronome = 'practice_metronome';
  // T15: a banda dos primeiros níveis da leitura (ligada e volume).
  static const _kBandOn = 'practice_band_on';
  static const _kBandVolume = 'practice_band_volume';
  static const _kPracticeMode = 'practice_mode';
  static const _kHighlightColor = 'ui_highlight_color';
  static const _kPracticePendingColor = 'ui_practice_pending_color';
  static const _kPracticeWrongColor = 'ui_practice_wrong_color';
  static const _kHaloWidth = 'ui_halo_width';
  static const _kBarColor = 'ui_bar_color';
  static const _kTrailMeasures = 'trail_measures';
  static const _kTrailPhases = 'trail_phases';
  static const _kTrailPhaseOrder = 'trail_phase_order';
  static const _kTrailSpeeds = 'trail_speeds';
  static const _kRhythmTolerance = 'rhythm_tolerance_ms';
  // I05 — nomes das notas na tela (D-LIC-NOMES): Dó–Ré–Mi ou C–D–E.
  // O interruptor nas configurações é do I09; aqui só a chave e o valor.
  static const _kNoteNaming = 'ui_note_naming';
  // EX03 (D-EXE-CIFRA): a grafia da cifra nas perguntas de acordes.
  static const _kChordNotation = 'ui_chord_notation';
  static const _kCourseTextScale = 'ui_course_text_scale';
  // Fase Q (Q03): "Abrir as músicas já sem acidentes".
  static const _kTransposeByDefault = 'score_transpose_default';
  static const _kKeyboardTranspose = 'midi_keyboard_transpose';
  // Layout da partitura, para todos os hinos: só o que a pessoa mudou.
  static const _kScoreLayout = 'score_layout';
  static const _kScorePageFitsBox = 'score_page_fits_box';

  final SharedPreferencesAsync _prefs;

  SoundOutput _output = SoundOutput.appSynth;
  bool _useScoreInstruments = false;
  // Ligado por padrão (U04): o primeiro play de uma instalação nova soa;
  // quem gravou desligado continua desligado (`load` só troca se há chave).
  bool _soundOn = true;
  bool _metronomeOn = false;
  bool _bandOn = true;
  int _bandVolume = 70;
  PracticeMode _practiceMode = PracticeMode.wait;
  // Verde, não o vermelho padrão do player: é também a cor da nota certa
  // no treino, e vermelho lá é a errada.
  Color _highlightColor = kPracticeCorrectColor;
  Color _practicePendingColor = kPracticePendingColor;
  Color _practiceWrongColor = kPracticeWrongColor;
  double _haloWidth = 1.0;
  Color _barColor = kDefaultBarColor;
  int _trailMeasures = kTrailDefaultMeasures;
  Set<TrailPhase> _trailPhases = {...TrailPhase.values};
  List<TrailPhase> _trailPhaseOrder = TrailPhase.values;
  Set<double> _trailSpeeds = {...kTrailSpeeds};
  double _rhythmToleranceMs = kDefaultRhythmToleranceMs;
  NoteNaming _noteNaming = NoteNaming.latin;
  ChordNotation _chordNotation = ChordNotation.brazilian;
  double _courseTextScale = 1.0;
  bool _transposeByDefault = false;
  Map<String, KeyboardTransposeBehavior> _keyboardTranspose = const {};
  Map<String, Object?> _scoreLayout = const {};
  bool _scorePageFitsBox = true;

  /// `true` depois do primeiro [load] — antes disso valem os padrões.
  bool get loaded => _loaded;
  bool _loaded = false;

  SoundOutput get output => _output;
  set output(SoundOutput value) {
    if (value == _output) return;
    _output = value;
    _changed(_prefs.setString(_kOutput, value.name));
  }

  /// Program Change (M03): manda o instrumento da partitura ao teclado MIDI
  /// — desligado por padrão, o usuário quer o som do próprio piano.
  bool get useScoreInstruments => _useScoreInstruments;
  set useScoreInstruments(bool value) {
    if (value == _useScoreInstruments) return;
    _useScoreInstruments = value;
    _changed(_prefs.setBool(_kUseScoreInstruments, value));
  }

  /// O som do app toca a partitura; desligado, o player só destaca as notas.
  bool get soundOn => _soundOn;
  set soundOn(bool value) {
    if (value == _soundOn) return;
    _soundOn = value;
    _changed(_prefs.setBool(_kSoundOn, value));
  }

  bool get metronomeOn => _metronomeOn;
  set metronomeOn(bool value) {
    if (value == _metronomeOn) return;
    _metronomeOn = value;
    _changed(_prefs.setBool(_kMetronome, value));
  }

  /// A banda que toca com o aluno nos primeiros níveis da leitura (T15),
  /// ligada por padrão.
  bool get bandOn => _bandOn;
  set bandOn(bool value) {
    if (value == _bandOn) return;
    _bandOn = value;
    _changed(_prefs.setBool(_kBandOn, value));
  }

  /// O volume da banda (0 a 100), 70 por padrão.
  int get bandVolume => _bandVolume;
  set bandVolume(int value) {
    final clamped = value.clamp(0, 100);
    if (clamped == _bandVolume) return;
    _bandVolume = clamped;
    _changed(_prefs.setInt(_kBandVolume, clamped));
  }

  /// Espera ou tempo real — o tipo de treino que "Espera" arma.
  PracticeMode get practiceMode => _practiceMode;
  set practiceMode(PracticeMode value) {
    if (value == _practiceMode) return;
    _practiceMode = value;
    _changed(_prefs.setString(_kPracticeMode, value.name));
  }

  /// Cor da nota destacada durante a execução — e, no treino, da nota que
  /// o aluno tocou certa.
  Color get highlightColor => _highlightColor;
  set highlightColor(Color value) {
    if (value == _highlightColor) return;
    _highlightColor = value;
    _changed(_prefs.setInt(_kHighlightColor, value.toARGB32()));
  }

  /// Treino: cor da nota que o app está esperando o aluno tocar.
  Color get practicePendingColor => _practicePendingColor;
  set practicePendingColor(Color value) {
    if (value == _practicePendingColor) return;
    _practicePendingColor = value;
    _changed(_prefs.setInt(_kPracticePendingColor, value.toARGB32()));
  }

  /// Treino: cor do pulso na nota esperada quando o aluno toca a tecla
  /// errada.
  Color get practiceWrongColor => _practiceWrongColor;
  set practiceWrongColor(Color value) {
    if (value == _practiceWrongColor) return;
    _practiceWrongColor = value;
    _changed(_prefs.setInt(_kPracticeWrongColor, value.toARGB32()));
  }

  /// Multiplicador do raio do halo da nota destacada; `0` desliga.
  double get haloWidth => _haloWidth;
  set haloWidth(double value) {
    if (value == _haloWidth) return;
    _haloWidth = value;
    _changed(_prefs.setDouble(_kHaloWidth, value));
  }

  /// Cor da haste que varre a página na virada.
  Color get barColor => _barColor;
  set barColor(Color value) {
    if (value == _barColor) return;
    _barColor = value;
    _changed(_prefs.setInt(_kBarColor, value.toARGB32()));
  }

  /// Compassos lógicos por trecho da trilha (J03): padrão 5, mínimo 3.
  int get trailMeasures => _trailMeasures;
  set trailMeasures(int value) {
    final clamped = value < kTrailMinMeasures ? kTrailMinMeasures : value;
    if (clamped == _trailMeasures) return;
    _trailMeasures = clamped;
    _changed(_prefs.setInt(_kTrailMeasures, clamped));
  }

  /// Etapas que entram na trilha de cada trecho (padrão: todas). Nunca
  /// vazio — tirar a última é ignorado.
  Set<TrailPhase> get trailPhases => _trailPhases;
  set trailPhases(Set<TrailPhase> value) {
    if (value.isEmpty || setEquals(value, _trailPhases)) return;
    _trailPhases = {...value};
    _changed(
      _prefs.setStringList(_kTrailPhases, [
        for (final p in TrailPhase.values)
          if (value.contains(p)) p.name,
      ]),
    );
  }

  /// Ordem das etapas em cada trecho (todas, marcadas ou não).
  List<TrailPhase> get trailPhaseOrder => _trailPhaseOrder;
  set trailPhaseOrder(List<TrailPhase> value) {
    final order = _completeOrder(value);
    if (listEquals(order, _trailPhaseOrder)) return;
    _trailPhaseOrder = order;
    _changed(
      _prefs.setStringList(_kTrailPhaseOrder, [for (final p in order) p.name]),
    );
  }

  /// As etapas que entram na trilha, na ordem escolhida.
  List<TrailPhase> get trailPlanPhases => [
    for (final p in _trailPhaseOrder)
      if (_trailPhases.contains(p)) p,
  ];

  /// [order] sem repetidas e com as que faltarem no fim (na ordem padrão).
  static List<TrailPhase> _completeOrder(Iterable<TrailPhase> order) {
    final seen = <TrailPhase>{...order};
    return List.unmodifiable([
      ...seen,
      for (final p in TrailPhase.values)
        if (!seen.contains(p)) p,
    ]);
  }

  /// Andamentos (de [kTrailSpeeds]) das etapas no ritmo dos trechos
  /// (padrão: todos). Nunca vazio.
  Set<double> get trailSpeeds => _trailSpeeds;
  set trailSpeeds(Set<double> value) {
    final valid = value.where(kTrailSpeeds.contains).toSet();
    if (valid.isEmpty || setEquals(valid, _trailSpeeds)) return;
    _trailSpeeds = valid;
    _changed(
      _prefs.setStringList(_kTrailSpeeds, [
        for (final s in kTrailSpeeds)
          if (valid.contains(s)) '${(s * 100).round()}',
      ]),
    );
  }

  /// Margem do tempo real em ms no andamento original (ver
  /// `PracticeController.rhythmToleranceMs`), entre
  /// [kMinRhythmToleranceMs] e [kMaxRhythmToleranceMs].
  double get rhythmToleranceMs => _rhythmToleranceMs;
  set rhythmToleranceMs(double value) {
    final v = value.clamp(kMinRhythmToleranceMs, kMaxRhythmToleranceMs);
    if (v == _rhythmToleranceMs) return;
    _rhythmToleranceMs = v;
    _changed(_prefs.setDouble(_kRhythmTolerance, v));
  }

  /// Nomes das notas na tela (I05, D-LIC-NOMES): `latin` (Dó–Ré–Mi, padrão)
  /// ou `letters` (C–D–E). O arquivo do curso usa sempre `C4`.
  NoteNaming get noteNaming => _noteNaming;
  set noteNaming(NoteNaming value) {
    if (value == _noteNaming) return;
    _noteNaming = value;
    _changed(_prefs.setString(_kNoteNaming, value.wire));
  }

  /// Como a cifra é escrita nas perguntas de acordes (EX03, D-EXE-CIFRA):
  /// `brazilian` (`C7M`, `Cm7(b5)`, o padrão) ou `american` (`Cmaj7`,
  /// `Cm7b5`). Um curso que fixa a sua (`chord-notation:`) não segue isto.
  ChordNotation get chordNotation => _chordNotation;
  set chordNotation(ChordNotation value) {
    if (value == _chordNotation) return;
    _chordNotation = value;
    _changed(_prefs.setString(_kChordNotation, value.name));
  }

  /// Multiplicador do texto nas telas dos cursos (lista, curso, lição,
  /// exercício), por cima do tamanho de fonte do sistema; entre
  /// [kMinCourseTextScale] e [kMaxCourseTextScale].
  double get courseTextScale => _courseTextScale;
  set courseTextScale(double value) {
    final v = value.clamp(kMinCourseTextScale, kMaxCourseTextScale);
    if (v == _courseTextScale) return;
    _courseTextScale = v;
    _changed(_prefs.setDouble(_kCourseTextScale, v));
  }

  /// "Abrir as músicas já sem acidentes" (fase Q): as que não têm escolha
  /// própria (`PieceSettings.transpose`) abrem transpostas para a armadura
  /// vazia. Desligado por padrão.
  bool get transposeByDefault => _transposeByDefault;
  set transposeByDefault(bool value) {
    if (value == _transposeByDefault) return;
    _transposeByDefault = value;
    _changed(_prefs.setBool(_kTransposeByDefault, value));
  }

  /// A última música aberta nesta execução do app estava transposta (Q07): o
  /// teclado pode ter ficado com o TRANSPOSE ligado. Vale só até fechar o app,
  /// por isso não é guardado nem avisa quem escuta.
  bool lastPieceTransposed = false;

  /// O que se sabe do TRANSPOSE de cada teclado, pelo nome do dispositivo MIDI
  /// (fase Q, Q06 preenche). Teclado não conferido: [KeyboardTransposeBehavior.unknown].
  KeyboardTransposeBehavior keyboardTransposeOf(String? deviceName) =>
      _keyboardTranspose[deviceName] ?? KeyboardTransposeBehavior.unknown;

  void setKeyboardTranspose(
    String deviceName,
    KeyboardTransposeBehavior behavior,
  ) {
    if (keyboardTransposeOf(deviceName) == behavior) return;
    _keyboardTranspose = {..._keyboardTranspose, deviceName: behavior};
    _changed(
      _prefs.setString(
        _kKeyboardTranspose,
        jsonEncode({
          for (final e in _keyboardTranspose.entries)
            e.key: {'out': ?e.value.shiftsOut, 'in': ?e.value.shiftsIn},
        }),
      ),
    );
  }

  static Map<String, KeyboardTransposeBehavior> _decodeKeyboardTranspose(
    String? text,
  ) {
    if (text == null) return const {};
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (e.value case final Map<String, dynamic> v)
            e.key: KeyboardTransposeBehavior(
              shiftsOut: v['out'] as bool?,
              shiftsIn: v['in'] as bool?,
            ),
      };
    } on Object {
      return const {};
    }
  }

  /// As opções do Verovio que a pessoa mudou, para todos os hinos. O que não
  /// está aqui segue o padrão do aparelho: o tamanho da notação no celular não
  /// é o do tablet. Os valores vêm como foram gravados: quem os usa passa por
  /// `layoutOverridesFrom` (lib/render/layout_options.dart), que descarta o
  /// que não serve mais.
  Map<String, Object?> get scoreLayout => _scoreLayout;

  void setScoreLayout(Map<String, Object> value) {
    if (mapEquals(value, _scoreLayout)) return;
    _scoreLayout = Map.unmodifiable(value);
    _changed(
      value.isEmpty
          ? _prefs.remove(_kScoreLayout)
          : _prefs.setString(_kScoreLayout, jsonEncode(value)),
    );
  }

  /// A página acompanha a área da partitura (padrão) ou usa `pageWidth` e
  /// `pageHeight`. Vale para todos os hinos.
  bool get scorePageFitsBox => _scorePageFitsBox;
  set scorePageFitsBox(bool value) {
    if (value == _scorePageFitsBox) return;
    _scorePageFitsBox = value;
    _changed(_prefs.setBool(_kScorePageFitsBox, value));
  }

  static Map<String, Object?> _decodeScoreLayout(String? text) {
    if (text == null) return const {};
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on Object {
      return const {};
    }
  }

  /// As configurações que mexem no que o aluno vê e ouve, para o relatório
  /// de bug e o log (cores em hexadecimal).
  Map<String, Object?> diagSnapshot() {
    String hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
    return {
      'saida': _output.name,
      'somLigado': _soundOn,
      'instrumentosDaPartitura': _useScoreInstruments,
      'metronomo': _metronomeOn,
      'banda': _bandOn,
      'volumeDaBanda': _bandVolume,
      'modoDeTreino': _practiceMode.name,
      'corDestaque': hex(_highlightColor),
      'corPendente': hex(_practicePendingColor),
      'corErro': hex(_practiceWrongColor),
      'brilho': _haloWidth,
      'corDaHaste': hex(_barColor),
      'margemDoRitmoMs': _rhythmToleranceMs,
      'nomeDasNotas': _noteNaming.name,
      'cifra': _chordNotation.name,
      'escalaDoTexto': _courseTextScale,
      'transporPorPadrao': _transposeByDefault,
      'layoutDaPartitura': _scoreLayout,
      'paginaCabeNaCaixa': _scorePageFitsBox,
    };
  }

  String? _diagLast;

  /// Grava no log o que mudou nas configurações desde a última vez.
  void _diagLogChange(String why) {
    try {
      final now = jsonEncode(diagSnapshot());
      if (now == _diagLast) return;
      final before = _diagLast == null
          ? const <String, Object?>{}
          : (jsonDecode(_diagLast!) as Map<String, Object?>);
      _diagLast = now;
      final after = jsonDecode(now) as Map<String, Object?>;
      final diff = {
        for (final e in after.entries)
          if (jsonEncode(before[e.key]) != jsonEncode(e.value))
            e.key: before.containsKey(e.key)
                ? '${jsonEncode(before[e.key])} → ${jsonEncode(e.value)}'
                : jsonEncode(e.value),
      };
      DiagLog.log(
        'config',
        before.isEmpty ? '$why: $now' : '$why: ${jsonEncode(diff)}',
      );
    } on Object {
      // O log nunca derruba as configurações.
    }
  }

  void _changed(Future<void> write) {
    notifyListeners();
    _diagLogChange('mudou');
    write.catchError((Object e) {
      debugPrint('configurações: não deu para gravar ($e)');
    });
  }

  /// Lê tudo do armazenamento. Cada chave por si: uma estragada não derruba
  /// as outras.
  Future<void> load() async {
    Future<T?> read<T>(Future<T?> Function() get) async {
      try {
        return await get();
      } on Object {
        return null;
      }
    }

    T? byName<T extends Enum>(List<T> values, String? name) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return null;
    }

    final output = await read(() => _prefs.getString(_kOutput));
    final instruments = await read(() => _prefs.getBool(_kUseScoreInstruments));
    final soundOn = await read(() => _prefs.getBool(_kSoundOn));
    final metronome = await read(() => _prefs.getBool(_kMetronome));
    final bandOn = await read(() => _prefs.getBool(_kBandOn));
    final bandVolume = await read(() => _prefs.getInt(_kBandVolume));
    final mode = await read(() => _prefs.getString(_kPracticeMode));
    final highlight = await read(() => _prefs.getInt(_kHighlightColor));
    final pending = await read(() => _prefs.getInt(_kPracticePendingColor));
    final wrong = await read(() => _prefs.getInt(_kPracticeWrongColor));
    final halo = await read(() => _prefs.getDouble(_kHaloWidth));
    final bar = await read(() => _prefs.getInt(_kBarColor));
    final trailMeasures = await read(() => _prefs.getInt(_kTrailMeasures));
    final trailPhases = await read(() => _prefs.getStringList(_kTrailPhases));
    final trailSpeeds = await read(() => _prefs.getStringList(_kTrailSpeeds));
    final phaseOrder = await read(
      () => _prefs.getStringList(_kTrailPhaseOrder),
    );
    final tolerance = await read(() => _prefs.getDouble(_kRhythmTolerance));
    final noteNaming = await read(() => _prefs.getString(_kNoteNaming));
    final chordNotation = await read(() => _prefs.getString(_kChordNotation));
    final textScale = await read(() => _prefs.getDouble(_kCourseTextScale));
    final transposeByDefault = await read(
      () => _prefs.getBool(_kTransposeByDefault),
    );
    final keyboardTranspose = await read(
      () => _prefs.getString(_kKeyboardTranspose),
    );
    final scoreLayout = await read(() => _prefs.getString(_kScoreLayout));
    final scorePageFitsBox = await read(
      () => _prefs.getBool(_kScorePageFitsBox),
    );

    _output = byName(SoundOutput.values, output) ?? _output;
    _useScoreInstruments = instruments ?? _useScoreInstruments;
    _soundOn = soundOn ?? _soundOn;
    _metronomeOn = metronome ?? _metronomeOn;
    _bandOn = bandOn ?? _bandOn;
    if (bandVolume != null) _bandVolume = bandVolume.clamp(0, 100);
    _practiceMode = byName(PracticeMode.values, mode) ?? _practiceMode;
    if (highlight != null) _highlightColor = Color(highlight);
    if (pending != null) _practicePendingColor = Color(pending);
    if (wrong != null) _practiceWrongColor = Color(wrong);
    if (halo != null) _haloWidth = halo.clamp(0.0, 3.0);
    if (bar != null) _barColor = Color(bar);
    if (trailMeasures != null) {
      _trailMeasures = trailMeasures < kTrailMinMeasures
          ? kTrailMinMeasures
          : trailMeasures;
    }
    if (trailPhases != null) {
      final phases = {
        for (final name in trailPhases) ?byName(TrailPhase.values, name),
      };
      if (phases.isNotEmpty) _trailPhases = phases;
    }
    if (phaseOrder != null) {
      _trailPhaseOrder = _completeOrder([
        for (final name in phaseOrder) ?byName(TrailPhase.values, name),
      ]);
    }
    if (trailSpeeds != null) {
      final speeds = {
        for (final s in kTrailSpeeds)
          if (trailSpeeds.contains('${(s * 100).round()}')) s,
      };
      if (speeds.isNotEmpty) _trailSpeeds = speeds;
    }
    if (tolerance != null) {
      _rhythmToleranceMs = tolerance.clamp(
        kMinRhythmToleranceMs,
        kMaxRhythmToleranceMs,
      );
    }
    _noteNaming = NoteNaming.fromWire(noteNaming);
    _chordNotation =
        byName(ChordNotation.values, chordNotation) ?? _chordNotation;
    if (textScale != null) {
      _courseTextScale = textScale.clamp(
        kMinCourseTextScale,
        kMaxCourseTextScale,
      );
    }
    _transposeByDefault = transposeByDefault ?? _transposeByDefault;
    _keyboardTranspose = _decodeKeyboardTranspose(keyboardTranspose);
    _scoreLayout = _decodeScoreLayout(scoreLayout);
    _scorePageFitsBox = scorePageFitsBox ?? _scorePageFitsBox;
    _loaded = true;
    DiagLog.setState('configuracoes', diagSnapshot);
    _diagLogChange('carregadas');
    notifyListeners();
  }
}
