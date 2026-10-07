import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_library/legacy_migration.dart';
import 'package:zywny_library/library_keys.dart';
import 'package:zywny_library/piece_progress.dart';
import 'package:zywny/settings/piece_settings.dart';
import 'package:zywny/trail/trail_progress.dart';

void main() {
  late SharedPreferencesAsync prefs;
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    prefs = SharedPreferencesAsync();
  });

  Future<void> seedOld() async {
    await prefs.setString(
      'hymn_progress',
      jsonEncode({
        '5': {'t': 1700000000000, 's': 78},
        '244': {'s': 90},
      }),
    );
    await prefs.setString(
      'hymn_settings_5',
      jsonEncode(const PieceSettings(speed: 0.8).toJson()),
    );
    await prefs.setString(
      'trail_5',
      jsonEncode(const TrailProgress(n: 5, total: 20).toJson()),
    );
    await prefs.setString(
      'trail_244',
      jsonEncode(const TrailProgress(n: 5, total: 30).toJson()),
    );
    await prefs.setString('library_active', 'hinos'); // não é de hino: fica
  }

  test('as três chaves antigas viram as novas e as antigas somem', () async {
    await seedOld();
    expect(await migrateLegacyHymnKeys(prefs), isTrue);

    final progress = PieceProgressStore(prefs: prefs);
    await progress.load('hinos');
    expect(progress['005']!.bestScore, 78);
    expect(progress['005']!.lastOpened!.millisecondsSinceEpoch, 1700000000000);
    expect(progress['244']!.bestScore, 90);

    final settings = await PieceSettingsStore(prefs: prefs)
        .load('hinos', '005');
    expect(settings.speed, 0.8);

    final trail = TrailProgressStore(prefs: prefs);
    await trail.load(const ['005', '244'], 'hinos');
    expect(trail['005'].total, 20);
    expect(trail['244'].total, 30);

    expect(await prefs.getString('hymn_progress'), isNull);
    expect(await prefs.getString('hymn_settings_5'), isNull);
    expect(await prefs.getString('trail_5'), isNull);
    expect(await prefs.getString('trail_244'), isNull);
    expect(await prefs.getString('library_active'), 'hinos');
    expect(await prefs.getBool(kLegacyMigratedKey), isTrue);
  });

  test('rodar de novo não faz nada, mesmo com chaves antigas novas', () async {
    await seedOld();
    await migrateLegacyHymnKeys(prefs);
    await prefs.setString('trail_9', '{"n":5,"total":3,"records":{}}');
    expect(await migrateLegacyHymnKeys(prefs), isFalse);
    expect(await prefs.getString('trail_9'), isNotNull);
    expect(await prefs.getString(trailKeyFor('hinos', '009')), isNull);
  });

  test('sem nada antigo: só põe a marca', () async {
    expect(await migrateLegacyHymnKeys(prefs), isTrue);
    expect(await prefs.getBool(kLegacyMigratedKey), isTrue);
    expect(await prefs.getKeys(), {kLegacyMigratedKey});
  });

  test('o que já existe na chave nova vence o antigo', () async {
    await seedOld();
    await prefs.setString(
      progressKeyFor('hinos'),
      jsonEncode({
        '005': {'s': 99},
      }),
    );
    await prefs.setString(
      trailKeyFor('hinos', '005'),
      jsonEncode(const TrailProgress(n: 4, total: 77).toJson()),
    );
    await migrateLegacyHymnKeys(prefs);
    final progress = PieceProgressStore(prefs: prefs);
    await progress.load('hinos');
    expect(progress['005']!.bestScore, 99); // novo vence
    expect(progress['244']!.bestScore, 90); // o resto veio do antigo
    final trail = TrailProgressStore(prefs: prefs);
    await trail.load(const ['005'], 'hinos');
    expect(trail['005'].total, 77);
    expect(await prefs.getString('trail_5'), isNull);
  });

  test('progresso antigo ilegível fica onde está, sem perda', () async {
    await prefs.setString('hymn_progress', '{quebrado');
    await prefs.setString('hymn_settings_3', '{"v":1}');
    await migrateLegacyHymnKeys(prefs);
    expect(await prefs.getString('hymn_progress'), '{quebrado');
    expect(
      await prefs.getString(pieceSettingsKeyFor('hinos', '003')),
      '{"v":1}',
    );
  });

  test(
    'chaves de biblioteca nova não são confundidas com as antigas',
    () async {
      await prefs.setString(trailKeyFor('classicos', '1'), '{}');
      await prefs.setString(pieceSettingsKeyFor('classicos', '1'), '{}');
      await migrateLegacyHymnKeys(prefs);
      expect(await prefs.getString(trailKeyFor('classicos', '1')), '{}');
      expect(
        await prefs.getString(pieceSettingsKeyFor('classicos', '1')),
        '{}',
      );
    },
  );
}
