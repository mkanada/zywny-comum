import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:score_bridge/score_bridge.dart' show kDefaultBarColor;
import 'package:shared_preferences/shared_preferences.dart';

import '../course/note_names.dart' show NoteNaming;
import '../practice/practice_colors.dart'
    show kPracticeCorrectColor, kPracticePendingColor, kPracticeWrongColor;
import '../practice/practice_controller.dart'
    show PracticeMode, kDefaultRhythmToleranceMs;
import '../trail/trail_stage.dart'
    show TrailPhase, kTrailDefaultMeasures, kTrailMinMeasures, kTrailSpeeds;

/// Limites da margem do tempo real nas configurações.
const double kMinRhythmToleranceMs = 30;
const double kMaxRhythmToleranceMs = 200;

/// Limites do tamanho do texto dos cursos (o "Aa" da lição).
const double kMinCourseTextScale = 0.85;
const double kMaxCourseTextScale = 2.0;

/// Saída de som (K03/M03): o sintetizador do app (`.sf2`) ou o teclado MIDI
/// conectado, tocando no som próprio do piano digital do usuário.
enum SoundOutput { appSynth, midiKeyboard }

/// Configurações **gerais** do app — valem para qualquer hino: som, saída,
/// metrônomo, cores. (O que é de um hino só — tamanho da notação, layout,
/// andamento, mão — fica em `PieceSettingsStore`.)
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
  static const _kCourseTextScale = 'ui_course_text_scale';
  // Fase Q (Q03): "Abrir as músicas já sem acidentes".
  static const _kTransposeByDefault = 'score_transpose_default';

  final SharedPreferencesAsync _prefs;

  SoundOutput _output = SoundOutput.appSynth;
  bool _useScoreInstruments = false;
  // Ligado por padrão (U04): o primeiro play de uma instalação nova soa;
  // quem gravou desligado continua desligado (`load` só troca se há chave).
  bool _soundOn = true;
  bool _metronomeOn = false;
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
  double _courseTextScale = 1.0;
  bool _transposeByDefault = false;

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

  void _changed(Future<void> write) {
    notifyListeners();
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
    final textScale = await read(() => _prefs.getDouble(_kCourseTextScale));
    final transposeByDefault = await read(
      () => _prefs.getBool(_kTransposeByDefault),
    );

    _output = byName(SoundOutput.values, output) ?? _output;
    _useScoreInstruments = instruments ?? _useScoreInstruments;
    _soundOn = soundOn ?? _soundOn;
    _metronomeOn = metronome ?? _metronomeOn;
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
    if (textScale != null) {
      _courseTextScale = textScale.clamp(
        kMinCourseTextScale,
        kMaxCourseTextScale,
      );
    }
    _transposeByDefault = transposeByDefault ?? _transposeByDefault;
    _loaded = true;
    notifyListeners();
  }
}
