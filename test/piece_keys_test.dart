import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_library/library_keys.dart';
import 'package:zywny_library/library_sort.dart';
import 'package:zywny_library/piece.dart';
import 'package:zywny_library/piece_progress.dart';
import 'package:zywny/settings/piece_settings.dart';
import 'package:zywny/trail/trail_progress.dart';

Piece _piece(String lib, String id, String title, {int? number}) => Piece(
  libraryId: lib,
  id: id,
  number: number,
  title: title,
  composer: 'C',
  titleKey: foldForSearch(title),
  composerKey: 'c',
  searchKey: foldForSearch('${number ?? ''} $title c'),
);

void main() {
  late SharedPreferencesAsync prefs;
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    prefs = SharedPreferencesAsync();
  });

  test('as chaves seguem o B00', () {
    expect(progressKeyFor('hinos'), 'lib_progress_hinos');
    expect(pieceSettingsKeyFor('hinos', '005'), 'piece_settings_hinos_005');
    expect(trailKeyFor('classicos', 'op100-2'), 'trail_classicos_op100-2');
  });

  group('cada biblioteca tem o seu progresso', () {
    test('mesmo id em duas bibliotecas não se mistura', () async {
      final store = PieceProgressStore(prefs: prefs);
      await store.load('a');
      await store.recordScore('1', 70);
      await store.load('b');
      expect(store['1'], isNull);
      await store.recordScore('1', 40);
      await store.load('a');
      expect(store['1']!.bestScore, 70);
      expect(store.libraryId, 'a');
      expect(await prefs.getString('lib_progress_a'), isNotNull);
      expect(await prefs.getString('lib_progress_b'), isNotNull);
    });

    test('a trilha carrega as músicas do catálogo, não 1..600', () async {
      final trail = TrailProgressStore(prefs: prefs);
      await trail.load(const ['x'], 'lib');
      await trail.save('x', const TrailProgress(n: 5, total: 9));
      await trail.save('y', const TrailProgress(n: 5, total: 4));
      final again = TrailProgressStore(prefs: prefs);
      await again.load(const ['x', 'z'], 'lib');
      expect(again['x'].total, 9);
      expect(again['y'], TrailProgress.empty); // y não está no catálogo
      expect(await prefs.getString('trail_lib_y'), isNotNull); // mas existe
    });

    test('ajustes por biblioteca + música; padrão apaga a chave', () async {
      final store = PieceSettingsStore(prefs: prefs);
      await store.save('a', '1', const PieceSettings(speed: 0.5));
      expect((await store.load('a', '1')).speed, 0.5);
      expect((await store.load('b', '1')).isDefault, isTrue);
      await store.save('a', '1', const PieceSettings());
      expect(await prefs.getString('piece_settings_a_1'), isNull);
    });

    test('remover a biblioteca (store) não apaga o progresso', () async {
      // O LibraryStore só mexe no pacote e na lista (library_store_test);
      // aqui, que as chaves de progresso não dependem dela.
      final store = PieceProgressStore(prefs: prefs);
      await store.load('hinos');
      await store.recordScore('001', 88);
      final again = PieceProgressStore(prefs: prefs);
      await again.load('hinos');
      expect(again['001']!.bestScore, 88);
    });
  });

  group('músicas sem número', () {
    final pieces = [
      _piece('c', 'op100-10', 'Dez'),
      _piece('c', 'op100-2', 'Dois'),
      _piece('c', 'op100-1', 'Um'),
    ];

    test('o id, em ordem natural, ordena no lugar do número', () {
      final sorted = sortedPieces(
        pieces,
        const SortState(),
        PieceProgressStore(prefs: prefs),
      );
      expect(sorted.map((p) => p.id), ['op100-1', 'op100-2', 'op100-10']);
    });

    test('busca por dígitos não acha música sem número', () {
      expect(filterPieces(pieces, '1'), isEmpty);
      expect(filterPieces(pieces, 'dois').map((p) => p.id), ['op100-2']);
    });

    test('o progresso é pelo id', () async {
      final progress = PieceProgressStore(prefs: prefs);
      await progress.load('c');
      await progress.recordScore('op100-2', 80);
      final sorted = sortedPieces(
        pieces,
        const SortState(key: SortKey.score, ascending: false),
        progress,
      );
      expect(sorted.first.id, 'op100-2');
    });
  });

  test('PieceCatalog.none não é erro e não abre partitura', () {
    const none = PieceCatalog.none();
    expect(none.hasLibrary, isFalse);
    expect(none.pieces, isEmpty);
    expect(() => none.loadScore(_piece('c', '1', 'T')), throwsStateError);
    expect(const PieceCatalog([]).hasLibrary, isTrue);
  });

  test('Piece sem id usa o número com três dígitos (índice de antes)', () {
    final p = Piece.fromJson({
      'n': 7,
      't': 'T',
      'c': 'C',
      'k': 't',
      'ck': 'c',
      'q': '7 t c',
    });
    expect(p.id, '007');
    expect(p.libraryId, 'hinos');
  });
}
