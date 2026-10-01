import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../layout_options.dart';
import '../practice/hand.dart';
import '../trail/trail_stage.dart' show kTrailMinMeasures;

/// Andamento que o app aceita (25%–150%, a faixa da gaveta de estudo).
const double kSpeedMin = 0.25;
const double kSpeedMax = 1.5;

/// Configuração **de um hino**: como a partitura dele é gravada (tamanho da
/// notação e as outras opções de layout) e como ele é estudado (andamento e
/// mão). Cada hino tem a sua; o que vale para todos está em `AppSettings`.
@immutable
class HymnSettings {
  const HymnSettings({
    this.layout = const {},
    this.pageFitsBox = true,
    this.speed,
    this.hand,
    this.trailMeasures,
  });

  /// Só as opções de layout que o usuário tirou do padrão do app (por nome,
  /// ver `kLayoutGroups`). O resto segue o padrão — inclusive se uma versão
  /// nova do app mudar esse padrão.
  final Map<String, Object> layout;

  /// A página acompanha a área da partitura (padrão) ou usa
  /// `pageWidth`/`pageHeight`.
  final bool pageFitsBox;

  /// `null` = o padrão (100%, ambas as mãos).
  final double? speed;
  final Hand? hand;

  /// Compassos por trecho só deste hino (J03); `null` = usa o geral.
  final int? trailMeasures;

  bool get isDefault =>
      layout.isEmpty &&
      pageFitsBox &&
      speed == null &&
      hand == null &&
      trailMeasures == null;

  /// Todas as opções de layout: [defaults] com o que este hino mudou.
  Map<String, Object> layoutOver(Map<String, Object> defaults) => {
    ...defaults,
    ...layout,
  };

  /// O que em [values] difere de [defaults] — o que vale a pena guardar.
  static Map<String, Object> layoutOverrides(
    Map<String, Object> values,
    Map<String, Object> defaults,
  ) => {
    for (final e in values.entries)
      if (defaults[e.key] != e.value) e.key: e.value,
  };

  Map<String, Object> toJson() => {
    'v': 1,
    if (layout.isNotEmpty) 'layout': layout,
    if (!pageFitsBox) 'fit': false,
    'speed': ?speed,
    'hand': ?hand?.name,
    'trailMeasures': ?trailMeasures,
  };

  /// Lê o que foi guardado, descartando o que não serve mais: opção que o
  /// app deixou de ter, valor de outro tipo, escolha que saiu da lista. Os
  /// números são trazidos para a faixa da opção. Assim um JSON gravado por
  /// outra versão do app nunca chega torto ao Verovio.
  factory HymnSettings.fromJson(Map<String, dynamic> json) {
    final layout = <String, Object>{};
    final stored = json['layout'];
    if (stored is Map) {
      for (final group in kLayoutGroups) {
        for (final option in group.options) {
          final value = _coerce(option, stored[option.key]);
          if (value != null) layout[option.key] = value;
        }
      }
    }
    final speed = json['speed'];
    Hand? hand;
    for (final h in Hand.values) {
      if (h.name == json['hand']) hand = h;
    }
    final trailMeasures = json['trailMeasures'];
    return HymnSettings(
      layout: layout,
      pageFitsBox: json['fit'] != false,
      speed: speed is num ? speed.toDouble().clamp(kSpeedMin, kSpeedMax) : null,
      hand: hand,
      trailMeasures: trailMeasures is num
          ? trailMeasures.round() < kTrailMinMeasures
                ? kTrailMinMeasures
                : trailMeasures.round()
          : null,
    );
  }

  static Object? _coerce(LayoutOption option, Object? value) {
    switch (option.kind) {
      case LayoutOptionKind.integer:
        return value is num
            ? value.round().clamp(option.min.toInt(), option.max.toInt())
            : null;
      case LayoutOptionKind.decimal:
        return value is num
            ? value.toDouble().clamp(
                option.min.toDouble(),
                option.max.toDouble(),
              )
            : null;
      case LayoutOptionKind.toggle:
        return value is bool ? value : null;
      case LayoutOptionKind.choice:
        return value is String && option.choices.contains(value) ? value : null;
    }
  }
}

/// Guarda um [HymnSettings] por hino em [SharedPreferencesAsync] (chave
/// `hymn_settings_<número>`), que sobrevive a fechar o app e a atualizá-lo.
/// Hino sem nada mudado não ocupa chave.
class HymnSettingsStore {
  HymnSettingsStore({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static String _key(int number) => 'hymn_settings_$number';

  Future<HymnSettings> load(int number) async {
    try {
      final text = await _prefs.getString(_key(number));
      if (text == null) return const HymnSettings();
      return HymnSettings.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      // Ilegível: o hino abre no padrão em vez de não abrir.
      return const HymnSettings();
    }
  }

  Future<void> save(int number, HymnSettings settings) => settings.isDefault
      ? _prefs.remove(_key(number))
      : _prefs.setString(_key(number), jsonEncode(settings.toJson()));
}
