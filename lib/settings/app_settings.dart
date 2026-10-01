import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:score_bridge/score_bridge.dart'
    show kDefaultBarColor, kDefaultHighlightColor;
import 'package:shared_preferences/shared_preferences.dart';

import '../practice/practice_controller.dart' show PracticeMode;
import '../trail/trail_stage.dart'
    show kTrailDefaultMeasures, kTrailMinMeasures;

/// Saída de som (K03/M03): o sintetizador do app (`.sf2`) ou o teclado MIDI
/// conectado, tocando no som próprio do piano digital do usuário.
enum SoundOutput { appSynth, midiKeyboard }

/// Configurações **gerais** do app — valem para qualquer hino: som, saída,
/// metrônomo, cores. (O que é de um hino só — tamanho da notação, layout,
/// andamento, mão — fica em `HymnSettingsStore`.)
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
  static const _kCountIn = 'practice_count_in';
  static const _kPracticeMode = 'practice_mode';
  static const _kHighlightColor = 'ui_highlight_color';
  static const _kHaloWidth = 'ui_halo_width';
  static const _kBarColor = 'ui_bar_color';
  static const _kTrailMeasures = 'trail_measures';

  final SharedPreferencesAsync _prefs;

  SoundOutput _output = SoundOutput.appSynth;
  bool _useScoreInstruments = false;
  bool _soundOn = false;
  bool _metronomeOn = false;
  bool _countInOn = false;
  PracticeMode _practiceMode = PracticeMode.wait;
  Color _highlightColor = kDefaultHighlightColor;
  double _haloWidth = 1.0;
  Color _barColor = kDefaultBarColor;
  int _trailMeasures = kTrailDefaultMeasures;

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

  /// Um compasso de contagem antes de o treino começar.
  bool get countInOn => _countInOn;
  set countInOn(bool value) {
    if (value == _countInOn) return;
    _countInOn = value;
    _changed(_prefs.setBool(_kCountIn, value));
  }

  /// Espera, tempo real ou ritmo — o tipo de treino que "Espera" arma.
  PracticeMode get practiceMode => _practiceMode;
  set practiceMode(PracticeMode value) {
    if (value == _practiceMode) return;
    _practiceMode = value;
    _changed(_prefs.setString(_kPracticeMode, value.name));
  }

  /// Cor da nota destacada durante a execução.
  Color get highlightColor => _highlightColor;
  set highlightColor(Color value) {
    if (value == _highlightColor) return;
    _highlightColor = value;
    _changed(_prefs.setInt(_kHighlightColor, value.toARGB32()));
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
    final countIn = await read(() => _prefs.getBool(_kCountIn));
    final mode = await read(() => _prefs.getString(_kPracticeMode));
    final highlight = await read(() => _prefs.getInt(_kHighlightColor));
    final halo = await read(() => _prefs.getDouble(_kHaloWidth));
    final bar = await read(() => _prefs.getInt(_kBarColor));
    final trailMeasures = await read(() => _prefs.getInt(_kTrailMeasures));

    _output = byName(SoundOutput.values, output) ?? _output;
    _useScoreInstruments = instruments ?? _useScoreInstruments;
    _soundOn = soundOn ?? _soundOn;
    _metronomeOn = metronome ?? _metronomeOn;
    _countInOn = countIn ?? _countInOn;
    _practiceMode = byName(PracticeMode.values, mode) ?? _practiceMode;
    if (highlight != null) _highlightColor = Color(highlight);
    if (halo != null) _haloWidth = halo.clamp(0.0, 3.0);
    if (bar != null) _barColor = Color(bar);
    if (trailMeasures != null) {
      _trailMeasures = trailMeasures < kTrailMinMeasures
          ? kTrailMinMeasures
          : trailMeasures;
    }
    _loaded = true;
    notifyListeners();
  }
}
