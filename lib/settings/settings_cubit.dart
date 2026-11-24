import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_diag/diag_log.dart';
import 'package:zywny_music/chord.dart' show ChordNotation;
import 'package:zywny_music/note_names.dart' show NoteNaming;

import '../practice/practice_mode.dart' show PracticeMode;
import '../trail/trail_stage.dart'
    show TrailPhase, kTrailMinMeasures, kTrailSpeeds;
import 'settings_state.dart';

export 'settings_state.dart';

/// As preferências lidas do armazenamento, uma por campo (`null` se não há).
typedef _Stored = ({
  String? output,
  bool? instruments,
  bool? soundOn,
  bool? metronome,
  String? mode,
  int? highlight,
  int? pending,
  int? wrong,
  int? student,
  double? halo,
  int? bar,
  int? trailMeasures,
  List<String>? trailPhases,
  List<String>? trailSpeeds,
  List<String>? phaseOrder,
  double? tolerance,
  double? repeatNotice,
  String? noteNaming,
  String? chordNotation,
  double? textScale,
  bool? transposeByDefault,
  String? keyboardTranspose,
  String? scoreLayout,
  bool? scorePageFitsBox,
});

/// Lê uma preferência; se o armazenamento falha, vale `null`.
Future<T?> _readPref<T>(Future<T?> Function() get) async {
  try {
    return await get();
  } on Object {
    return null;
  }
}

/// O valor do enum cujo nome é [name]; `null` se não há.
T? _byName<T extends Enum>(List<T> values, String? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// [order] sem repetidas e com as que faltarem no fim (na ordem padrão).
List<TrailPhase> _completeOrder(Iterable<TrailPhase> order) {
  final seen = <TrailPhase>{...order};
  return List.unmodifiable([
    ...seen,
    for (final p in TrailPhase.values)
      if (!seen.contains(p)) p,
  ]);
}

Map<String, KeyboardTransposeBehavior> _decodeKeyboardTranspose(String? text) {
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

Map<String, Object?> _decodeScoreLayout(String? text) {
  if (text == null) return const {};
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, Object?> ? decoded : const {};
  } on Object {
    return const {};
  }
}

/// As fases lidas; `null` se a chave não existe.
Set<TrailPhase>? _fasesLidas(List<String>? nomes) => nomes == null
    ? null
    : {for (final name in nomes) ?_byName(TrailPhase.values, name)};

/// Os andamentos lidos (os de `kTrailSpeeds` gravados); `null` se a chave não
/// existe.
Set<double>? _andamentosLidos(List<String>? nomes) => nomes == null
    ? null
    : {
        for (final s in kTrailSpeeds)
          if (nomes.contains('${(s * 100).round()}')) s,
      };

/// Configurações **gerais** do app (BL08, antes `AppSettings`, um
/// `ChangeNotifier`). Cada valor é uma chave própria em
/// [SharedPreferencesAsync], que no Android/Linux/Windows sobrevive a fechar o
/// app e a instalar uma versão nova por cima. Uma chave ausente ou ilegível
/// vale o padrão, então uma versão futura pode acrescentar ou abandonar chaves
/// sem migração.
///
/// Cada setter grava no armazenamento e emite o estado novo. Quem lê usa
/// `state` (síncrono, o motor também); a tela escuta `stream` por um
/// `BlocBuilder`. O aviso chega ao `stream` numa microtask, por isso quem
/// precisa do valor logo depois de mudar lê `state`, não espera o aviso.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync(),
      super(SettingsState());

  // `sound_output` e `sound_use_score_instruments` já existiam antes desta
  // classe (M03): os nomes ficam, para quem já tinha escolhido.
  static const _kOutput = 'sound_output';
  static const _kUseScoreInstruments = 'sound_use_score_instruments';
  static const _kSoundOn = 'sound_on';
  static const _kMetronome = 'practice_metronome';
  static const _kPracticeMode = 'practice_mode';
  static const _kHighlightColor = 'ui_highlight_color';
  static const _kPracticePendingColor = 'ui_practice_pending_color';
  static const _kPracticeWrongColor = 'ui_practice_wrong_color';
  static const _kStudentPartColor = 'ui_student_part_color';
  static const _kHaloWidth = 'ui_halo_width';
  static const _kBarColor = 'ui_bar_color';
  static const _kTrailMeasures = 'trail_measures';
  static const _kTrailPhases = 'trail_phases';
  static const _kTrailPhaseOrder = 'trail_phase_order';
  static const _kTrailSpeeds = 'trail_speeds';
  static const _kRhythmTolerance = 'rhythm_tolerance_ms';
  static const _kRepeatNotice = 'repeat_notice_seconds';
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

  /// A última música aberta nesta execução do app estava transposta (Q07): o
  /// teclado pode ter ficado com o TRANSPOSE ligado. Vale só até fechar o app,
  /// por isso não é guardado, não avisa quem escuta e não é estado.
  bool lastPieceTransposed = false;

  String? _diagLast;

  /// Grava [gravacao] e põe o estado novo; o log registra o que mudou.
  void _mudou(SettingsState novo, Future<void> gravacao) {
    emit(novo);
    _diagLogChange('mudou');
    gravacao.catchError((Object e) {
      debugPrint('configurações: não deu para gravar ($e)');
    });
  }

  /// Grava no log o que mudou nas configurações desde a última vez.
  void _diagLogChange(String why) {
    try {
      final now = jsonEncode(state.diagSnapshot());
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

  // --- Som e modo de treino -------------------------------------------------

  void setOutput(SoundOutput value) {
    if (value == state.output) return;
    _mudou(
      state.copyWith(output: value),
      _prefs.setString(_kOutput, value.name),
    );
  }

  /// Program Change (M03): manda o instrumento da partitura ao teclado MIDI.
  void setUseScoreInstruments(bool value) {
    if (value == state.useScoreInstruments) return;
    _mudou(
      state.copyWith(useScoreInstruments: value),
      _prefs.setBool(_kUseScoreInstruments, value),
    );
  }

  void setSoundOn(bool value) {
    if (value == state.soundOn) return;
    _mudou(state.copyWith(soundOn: value), _prefs.setBool(_kSoundOn, value));
  }

  void setMetronomeOn(bool value) {
    if (value == state.metronomeOn) return;
    _mudou(
      state.copyWith(metronomeOn: value),
      _prefs.setBool(_kMetronome, value),
    );
  }

  void setPracticeMode(PracticeMode value) {
    if (value == state.practiceMode) return;
    _mudou(
      state.copyWith(practiceMode: value),
      _prefs.setString(_kPracticeMode, value.name),
    );
  }

  // --- Cores e brilho -------------------------------------------------------

  void setHighlightColor(Color value) {
    if (value == state.highlightColor) return;
    _mudou(
      state.copyWith(highlightColor: value),
      _prefs.setInt(_kHighlightColor, value.toARGB32()),
    );
  }

  void setPracticePendingColor(Color value) {
    if (value == state.practicePendingColor) return;
    _mudou(
      state.copyWith(practicePendingColor: value),
      _prefs.setInt(_kPracticePendingColor, value.toARGB32()),
    );
  }

  void setPracticeWrongColor(Color value) {
    if (value == state.practiceWrongColor) return;
    _mudou(
      state.copyWith(practiceWrongColor: value),
      _prefs.setInt(_kPracticeWrongColor, value.toARGB32()),
    );
  }

  void setStudentPartColor(Color value) {
    if (value == state.studentPartColor) return;
    _mudou(
      state.copyWith(studentPartColor: value),
      _prefs.setInt(_kStudentPartColor, value.toARGB32()),
    );
  }

  void setHaloWidth(double value) {
    if (value == state.haloWidth) return;
    _mudou(
      state.copyWith(haloWidth: value),
      _prefs.setDouble(_kHaloWidth, value),
    );
  }

  void setBarColor(Color value) {
    if (value == state.barColor) return;
    _mudou(
      state.copyWith(barColor: value),
      _prefs.setInt(_kBarColor, value.toARGB32()),
    );
  }

  // --- Trilha ---------------------------------------------------------------

  void setTrailMeasures(int value) {
    final clamped = value < kTrailMinMeasures ? kTrailMinMeasures : value;
    if (clamped == state.trailMeasures) return;
    _mudou(
      state.copyWith(trailMeasures: clamped),
      _prefs.setInt(_kTrailMeasures, clamped),
    );
  }

  /// Nunca vazio: tirar a última etapa é ignorado.
  void setTrailPhases(Set<TrailPhase> value) {
    if (value.isEmpty || setEquals(value, state.trailPhases)) return;
    _mudou(
      state.copyWith(trailPhases: {...value}),
      _prefs.setStringList(_kTrailPhases, [
        for (final p in TrailPhase.values)
          if (value.contains(p)) p.name,
      ]),
    );
  }

  void setTrailPhaseOrder(List<TrailPhase> value) {
    final order = _completeOrder(value);
    if (listEquals(order, state.trailPhaseOrder)) return;
    _mudou(
      state.copyWith(trailPhaseOrder: order),
      _prefs.setStringList(_kTrailPhaseOrder, [for (final p in order) p.name]),
    );
  }

  /// Nunca vazio; os andamentos que não estão em `kTrailSpeeds` são ignorados.
  void setTrailSpeeds(Set<double> value) {
    final valid = value.where(kTrailSpeeds.contains).toSet();
    if (valid.isEmpty || setEquals(valid, state.trailSpeeds)) return;
    _mudou(
      state.copyWith(trailSpeeds: valid),
      _prefs.setStringList(_kTrailSpeeds, [
        for (final s in kTrailSpeeds)
          if (valid.contains(s)) '${(s * 100).round()}',
      ]),
    );
  }

  // --- Ritmo, texto e cifra -------------------------------------------------

  void setRhythmToleranceMs(double value) {
    final v = value.clamp(kMinRhythmToleranceMs, kMaxRhythmToleranceMs);
    if (v == state.rhythmToleranceMs) return;
    _mudou(
      state.copyWith(rhythmToleranceMs: v),
      _prefs.setDouble(_kRhythmTolerance, v),
    );
  }

  void setRepeatNoticeSeconds(double value) {
    final v = value.clamp(kMinRepeatNoticeSeconds, kMaxRepeatNoticeSeconds);
    if (v == state.repeatNoticeSeconds) return;
    _mudou(
      state.copyWith(repeatNoticeSeconds: v),
      _prefs.setDouble(_kRepeatNotice, v),
    );
  }

  void setNoteNaming(NoteNaming value) {
    if (value == state.noteNaming) return;
    _mudou(
      state.copyWith(noteNaming: value),
      _prefs.setString(_kNoteNaming, value.wire),
    );
  }

  void setChordNotation(ChordNotation value) {
    if (value == state.chordNotation) return;
    _mudou(
      state.copyWith(chordNotation: value),
      _prefs.setString(_kChordNotation, value.name),
    );
  }

  void setCourseTextScale(double value) {
    final v = value.clamp(kMinCourseTextScale, kMaxCourseTextScale);
    if (v == state.courseTextScale) return;
    _mudou(
      state.copyWith(courseTextScale: v),
      _prefs.setDouble(_kCourseTextScale, v),
    );
  }

  void setTransposeByDefault(bool value) {
    if (value == state.transposeByDefault) return;
    _mudou(
      state.copyWith(transposeByDefault: value),
      _prefs.setBool(_kTransposeByDefault, value),
    );
  }

  // --- Teclado MIDI e layout ------------------------------------------------

  void setKeyboardTranspose(
    String deviceName,
    KeyboardTransposeBehavior behavior,
  ) {
    if (state.keyboardTransposeOf(deviceName) == behavior) return;
    final mapa = {...state.keyboardTranspose, deviceName: behavior};
    _mudou(
      state.copyWith(keyboardTranspose: mapa),
      _prefs.setString(
        _kKeyboardTranspose,
        jsonEncode({
          for (final e in mapa.entries)
            e.key: {'out': ?e.value.shiftsOut, 'in': ?e.value.shiftsIn},
        }),
      ),
    );
  }

  void setScoreLayout(Map<String, Object> value) {
    if (mapEquals(value, state.scoreLayout)) return;
    _mudou(
      state.copyWith(scoreLayout: Map.unmodifiable(value)),
      value.isEmpty
          ? _prefs.remove(_kScoreLayout)
          : _prefs.setString(_kScoreLayout, jsonEncode(value)),
    );
  }

  void setScorePageFitsBox(bool value) {
    if (value == state.scorePageFitsBox) return;
    _mudou(
      state.copyWith(scorePageFitsBox: value),
      _prefs.setBool(_kScorePageFitsBox, value),
    );
  }

  // --- Carga ----------------------------------------------------------------

  /// Lê tudo do armazenamento. Cada chave por si: uma estragada não derruba
  /// as outras.
  Future<void> load() async {
    final stored = await _readStored();
    if (isClosed) return;
    emit(_lido(stored));
    DiagLog.setState('configuracoes', () => state.diagSnapshot());
    _diagLogChange('carregadas');
  }

  /// Lê todas as preferências guardadas. Uma que falha (ou não existe) vale
  /// `null`, e fica o padrão.
  Future<_Stored> _readStored() async => (
    output: await _readPref(() => _prefs.getString(_kOutput)),
    instruments: await _readPref(() => _prefs.getBool(_kUseScoreInstruments)),
    soundOn: await _readPref(() => _prefs.getBool(_kSoundOn)),
    metronome: await _readPref(() => _prefs.getBool(_kMetronome)),
    mode: await _readPref(() => _prefs.getString(_kPracticeMode)),
    highlight: await _readPref(() => _prefs.getInt(_kHighlightColor)),
    pending: await _readPref(() => _prefs.getInt(_kPracticePendingColor)),
    wrong: await _readPref(() => _prefs.getInt(_kPracticeWrongColor)),
    student: await _readPref(() => _prefs.getInt(_kStudentPartColor)),
    halo: await _readPref(() => _prefs.getDouble(_kHaloWidth)),
    bar: await _readPref(() => _prefs.getInt(_kBarColor)),
    trailMeasures: await _readPref(() => _prefs.getInt(_kTrailMeasures)),
    trailPhases: await _readPref(() => _prefs.getStringList(_kTrailPhases)),
    trailSpeeds: await _readPref(() => _prefs.getStringList(_kTrailSpeeds)),
    phaseOrder: await _readPref(() => _prefs.getStringList(_kTrailPhaseOrder)),
    tolerance: await _readPref(() => _prefs.getDouble(_kRhythmTolerance)),
    repeatNotice: await _readPref(() => _prefs.getDouble(_kRepeatNotice)),
    noteNaming: await _readPref(() => _prefs.getString(_kNoteNaming)),
    chordNotation: await _readPref(() => _prefs.getString(_kChordNotation)),
    textScale: await _readPref(() => _prefs.getDouble(_kCourseTextScale)),
    transposeByDefault: await _readPref(
      () => _prefs.getBool(_kTransposeByDefault),
    ),
    keyboardTranspose: await _readPref(
      () => _prefs.getString(_kKeyboardTranspose),
    ),
    scoreLayout: await _readPref(() => _prefs.getString(_kScoreLayout)),
    scorePageFitsBox: await _readPref(() => _prefs.getBool(_kScorePageFitsBox)),
  );

  /// O estado que sai do que foi lido: o que não veio fica como estava no
  /// estado atual (o padrão, na carga inicial). Cada grupo com a regra dele.
  SettingsState _lido(_Stored s) {
    final a = state;
    final fases = _fasesLidas(s.trailPhases);
    final ordem = s.phaseOrder;
    final velocidades = _andamentosLidos(s.trailSpeeds);
    final medidas = s.trailMeasures;
    final halo = s.halo;
    final tolerancia = s.tolerance;
    final aviso = s.repeatNotice;
    final escala = s.textScale;
    return a.copyWith(
      loaded: true,
      // O som (a saída, o timbre do teclado, se toca e o metrônomo) e o modo.
      output: _byName(SoundOutput.values, s.output) ?? a.output,
      useScoreInstruments: s.instruments ?? a.useScoreInstruments,
      soundOn: s.soundOn ?? a.soundOn,
      metronomeOn: s.metronome ?? a.metronomeOn,
      practiceMode: _byName(PracticeMode.values, s.mode) ?? a.practiceMode,
      // As cores da partitura e do treino, e o brilho em volta da nota.
      highlightColor: s.highlight == null
          ? a.highlightColor
          : Color(s.highlight!),
      practicePendingColor: s.pending == null
          ? a.practicePendingColor
          : Color(s.pending!),
      practiceWrongColor: s.wrong == null
          ? a.practiceWrongColor
          : Color(s.wrong!),
      studentPartColor: s.student == null
          ? a.studentPartColor
          : Color(s.student!),
      haloWidth: halo == null ? a.haloWidth : halo.clamp(0.0, 3.0),
      barColor: s.bar == null ? a.barColor : Color(s.bar!),
      // A trilha: o tamanho do trecho, as etapas (e a ordem) e os andamentos.
      // O que não é reconhecido fica de fora.
      trailMeasures: medidas == null
          ? a.trailMeasures
          : (medidas < kTrailMinMeasures ? kTrailMinMeasures : medidas),
      trailPhases: fases != null && fases.isNotEmpty ? fases : a.trailPhases,
      trailPhaseOrder: ordem == null
          ? a.trailPhaseOrder
          : _completeOrder([
              for (final name in ordem) ?_byName(TrailPhase.values, name),
            ]),
      trailSpeeds: velocidades != null && velocidades.isNotEmpty
          ? velocidades
          : a.trailSpeeds,
      // O texto e o resto: a margem do tempo, o aviso da volta, o nome das
      // notas, a cifra, o texto dos cursos, a transposição, o teclado e a
      // partitura.
      rhythmToleranceMs: tolerancia == null
          ? a.rhythmToleranceMs
          : tolerancia.clamp(kMinRhythmToleranceMs, kMaxRhythmToleranceMs),
      repeatNoticeSeconds: aviso == null
          ? a.repeatNoticeSeconds
          : aviso.clamp(kMinRepeatNoticeSeconds, kMaxRepeatNoticeSeconds),
      noteNaming: NoteNaming.fromWire(s.noteNaming),
      chordNotation:
          _byName(ChordNotation.values, s.chordNotation) ?? a.chordNotation,
      courseTextScale: escala == null
          ? a.courseTextScale
          : escala.clamp(kMinCourseTextScale, kMaxCourseTextScale),
      transposeByDefault: s.transposeByDefault ?? a.transposeByDefault,
      keyboardTranspose: _decodeKeyboardTranspose(s.keyboardTranspose),
      scoreLayout: _decodeScoreLayout(s.scoreLayout),
      scorePageFitsBox: s.scorePageFitsBox ?? a.scorePageFitsBox,
    );
  }
}
