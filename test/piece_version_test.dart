import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny/settings/piece_settings.dart';
import 'package:zywny_library/library_keys.dart';
import 'package:zywny_library/piece.dart';

Piece _piece() => Piece(
  number: 1,
  title: 'Santo',
  composer: 'Dykes',
  hasSimplified: true,
  fifths: 2,
  titleKey: 'santo',
  composerKey: 'dykes',
  searchKey: '1 santo dykes',
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('a versão simplificada tem id próprio e aponta para a música', () {
    final base = _piece();
    final simple = base.asSimplified();
    expect(simple.id, '001.s');
    expect(simple.baseId, '001');
    expect(base.baseId, '001');
    expect(simple.simplified, isTrue);
    expect(simple.hasSimplified, isFalse);
    expect(simple.title, base.title);
    expect(simple.number, base.number);
    expect(simple.fifths, 2);
    // Progresso e ajustes ficam em chaves separadas da completa.
    expect(trailKeyFor('hinos', progressIdFor(simple.id, null)), isNot(
      trailKeyFor('hinos', progressIdFor(base.id, null)),
    ));
  });

  test('a escolha da versão é lembrada por música; sem escolha, completa', () async {
    final store = PieceSettingsStore(prefs: SharedPreferencesAsync());
    expect(await store.loadSimplified('hinos', '001'), isFalse);
    await store.saveSimplified('hinos', '001', true);
    expect(await store.loadSimplified('hinos', '001'), isTrue);
    expect(await store.loadSimplified('hinos', '002'), isFalse);
    await store.saveSimplified('hinos', '001', false);
    expect(await store.loadSimplified('hinos', '001'), isFalse);
  });
}
