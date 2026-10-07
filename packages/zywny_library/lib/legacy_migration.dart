import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'library_keys.dart';
import 'piece.dart' show kHymnsLibraryId;

/// Marca de que a migração já rodou; impede repetir (D-BIB-MIGRAR).
const kLegacyMigratedKey = 'library_migrated_v1';

final _legacySettings = RegExp(r'^hymn_settings_(\d+)$');
final _legacyTrail = RegExp(r'^trail_(\d+)$');

/// Antes da fase B tudo era guardado pelo número do hino. Copia para as
/// chaves da biblioteca `hinos` (o id da música é o número com três
/// dígitos) e apaga as antigas:
///
/// | antes | depois |
/// | --- | --- |
/// | `hymn_progress` (número → `{t, s}`) | `lib_progress_hinos` (id → `{t, s}`) |
/// | `hymn_settings_<n>` | `piece_settings_hinos_<id>` |
/// | `trail_<n>` | `trail_hinos_<id>` |
///
/// Uma vez só, na primeira vez que a biblioteca de hinos aparece (instalada,
/// ou os hinos embutidos em depuração). Um valor que já exista na chave nova
/// vence o antigo. Um JSON antigo ilegível fica onde está, sem perda.
/// Devolve `false` se já tinha rodado.
Future<bool> migrateLegacyHymnKeys(SharedPreferencesAsync prefs) async {
  if (await prefs.getBool(kLegacyMigratedKey) ?? false) return false;
  String id(String digits) => int.parse(digits).toString().padLeft(3, '0');

  final oldProgress = await prefs.getString('hymn_progress');
  if (oldProgress != null) {
    try {
      final old = jsonDecode(oldProgress) as Map<String, dynamic>;
      final key = progressKeyFor(kHymnsLibraryId);
      final current = await prefs.getString(key);
      final merged = <String, dynamic>{
        for (final e in old.entries) id(e.key): e.value,
        if (current != null) ...jsonDecode(current) as Map<String, dynamic>,
      };
      await prefs.setString(key, jsonEncode(merged));
      await prefs.remove('hymn_progress');
    } on Object {
      // Ilegível: fica como está.
    }
  }

  for (final key in await prefs.getKeys()) {
    for (final (pattern, newKey) in [
      (_legacySettings, pieceSettingsKeyFor),
      (_legacyTrail, trailKeyFor),
    ]) {
      final match = pattern.firstMatch(key);
      if (match == null) continue;
      final to = newKey(kHymnsLibraryId, id(match[1]!));
      final value = await prefs.getString(key);
      if (value != null && await prefs.getString(to) == null) {
        await prefs.setString(to, value);
      }
      await prefs.remove(key);
    }
  }
  await prefs.setBool(kLegacyMigratedKey, true);
  return true;
}
