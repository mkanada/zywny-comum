import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zywny_library/library_keys.dart';

import 'package:zywny_music/transposition.dart';

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

/// Configuração **de um hino**: como ele é estudado (andamento, mão, trilha e
/// tom). Cada hino tem a sua. O que vale para todos fica em `AppSettings`,
/// inclusive o layout da partitura (`AppSettings.scoreLayout`).
@immutable
class PieceSettings {
  const PieceSettings({
    this.speed,
    this.hand,
    this.trailMeasures,
    this.transpose,
  });

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
      speed == null &&
      hand == null &&
      trailMeasures == null &&
      transpose == null;

  Map<String, Object> toJson() => {
    'v': 1,
    'speed': ?speed,
    'hand': ?hand?.name,
    'trailMeasures': ?trailMeasures,
    'tr': ?transpose,
  };

  /// Lê o que foi guardado, descartando o que não serve mais: valor de outro
  /// tipo, escolha que saiu da lista. Assim um JSON gravado por outra versão
  /// do app nunca chega torto ao andamento ou à trilha. (Um `layout` gravado
  /// antes, por hino, é ignorado: agora ele é de todos, `AppSettings`.)
  factory PieceSettings.fromJson(Map<String, dynamic> json) {
    final speed = json['speed'];
    Hand? hand;
    for (final h in Hand.values) {
      if (h.name == json['hand']) hand = h;
    }
    final trailMeasures = json['trailMeasures'];
    final transpose = json['tr'];
    return PieceSettings(
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

  /// Se a música abre na versão simplificada (a última escolha da pessoa).
  Future<bool> loadSimplified(String libraryId, String pieceId) async {
    try {
      return await _prefs.getBool(pieceVersionKeyFor(libraryId, pieceId)) ??
          false;
    } on Object {
      return false;
    }
  }

  Future<void> saveSimplified(
    String libraryId,
    String pieceId,
    bool simplified,
  ) {
    final key = pieceVersionKeyFor(libraryId, pieceId);
    return simplified ? _prefs.setBool(key, true) : _prefs.remove(key);
  }

  Future<void> save(String libraryId, String pieceId, PieceSettings settings) {
    final key = pieceSettingsKeyFor(libraryId, pieceId);
    return settings.isDefault
        ? _prefs.remove(key)
        : _prefs.setString(key, jsonEncode(settings.toJson()));
  }
}
