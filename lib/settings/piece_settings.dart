import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/layout_options.dart';
import '../library/library_keys.dart';
import '../music/transposition.dart';
import '../practice/hand.dart';
import '../trail/trail_stage.dart' show kTrailMinMeasures;

/// Andamento que o app aceita (25%–150%, a faixa da gaveta de estudo).
const double kSpeedMin = 0.25;
const double kSpeedMax = 1.5;

/// O que `PieceSettings.transpose` guarda quando a pessoa escolheu **não**
/// transpor esta música (o uníssono perfeito): vence a chave geral "abrir as
/// músicas já sem acidentes". `Transposition.parse` não o aceita — não é uma
/// transposição —, então quem lê o campo trata este valor antes.
const String kTransposeNone = 'P1';

/// Configuração **de um hino**: como a partitura dele é gravada (tamanho da
/// notação e as outras opções de layout) e como ele é estudado (andamento e
/// mão). Cada hino tem a sua; o que vale para todos está em `AppSettings`.
@immutable
class PieceSettings {
  const PieceSettings({
    this.layout = const {},
    this.pageFitsBox = true,
    this.speed,
    this.hand,
    this.trailMeasures,
    this.transpose,
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

  /// Transpor este hino (fase Q), o intervalo na sintaxe do Verovio (`-m3`).
  /// Três estados: `null` (a pessoa não escolheu: vale a chave geral
  /// `AppSettings.transposeByDefault`), [kTransposeNone] (escolheu "Não") e um
  /// intervalo que `Transposition.parse` aceita, já no texto canônico.
  final String? transpose;

  bool get isDefault =>
      layout.isEmpty &&
      pageFitsBox &&
      speed == null &&
      hand == null &&
      trailMeasures == null &&
      transpose == null;

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
    'tr': ?transpose,
  };

  /// Lê o que foi guardado, descartando o que não serve mais: opção que o
  /// app deixou de ter, valor de outro tipo, escolha que saiu da lista. Os
  /// números são trazidos para a faixa da opção. Assim um JSON gravado por
  /// outra versão do app nunca chega torto ao Verovio.
  factory PieceSettings.fromJson(Map<String, dynamic> json) {
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
    final transpose = json['tr'];
    return PieceSettings(
      layout: layout,
      pageFitsBox: json['fit'] != false,
      speed: speed is num ? speed.toDouble().clamp(kSpeedMin, kSpeedMax) : null,
      hand: hand,
      trailMeasures: trailMeasures is num
          ? trailMeasures.round() < kTrailMinMeasures
                ? kTrailMinMeasures
                : trailMeasures.round()
          : null,
      transpose: transpose is String ? _coerceTranspose(transpose) : null,
    );
  }

  /// [kTransposeNone], ou o texto canônico do intervalo; `null` se o que foi
  /// guardado não é nenhum dos dois (nunca chega torto ao Verovio).
  static String? _coerceTranspose(String text) {
    if (text == kTransposeNone) return kTransposeNone;
    return Transposition.parse(text)?.interval;
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

/// Guarda um [PieceSettings] por música em [SharedPreferencesAsync] (chave
/// `piece_settings_<biblioteca>_<id>`), que sobrevive a fechar o app e a
/// atualizá-lo. Música sem nada mudado não ocupa chave.
class PieceSettingsStore {
  PieceSettingsStore({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  Future<PieceSettings> load(String libraryId, String pieceId) async {
    try {
      final text = await _prefs.getString(
        pieceSettingsKeyFor(libraryId, pieceId),
      );
      if (text == null) return const PieceSettings();
      return PieceSettings.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      // Ilegível: a música abre no padrão em vez de não abrir.
      return const PieceSettings();
    }
  }

  Future<void> save(String libraryId, String pieceId, PieceSettings settings) {
    final key = pieceSettingsKeyFor(libraryId, pieceId);
    return settings.isDefault
        ? _prefs.remove(key)
        : _prefs.setString(key, jsonEncode(settings.toJson()));
  }
}
