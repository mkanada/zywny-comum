import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_library/piece_progress.dart';

void main() {
  late SharedPreferencesAsync prefs;
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    prefs = SharedPreferencesAsync();
  });

  final agora = DateTime(2026, 10, 6, 12);

  group('PieceProgressCubit', () {
    blocTest<PieceProgressCubit, PieceProgressState>(
      'marcar aberta emite a música com a hora de agora',
      build: () => PieceProgressCubit(prefs: prefs, now: () => agora),
      act: (c) => c.markOpened('001'),
      expect: () => [
        isA<PieceProgressState>().having(
          (s) => s.byId['001']?.lastOpened,
          'abertura',
          agora,
        ),
      ],
    );

    blocTest<PieceProgressCubit, PieceProgressState>(
      'pontuar só emite quando a nota sobe',
      build: () => PieceProgressCubit(prefs: prefs),
      act: (c) async {
        await c.recordScore('001', 70);
        await c.recordScore('001', 40); // pior: não emite
        await c.recordScore('001', 80);
      },
      expect: () => [
        isA<PieceProgressState>().having(
          (s) => s['001']?.bestScore,
          'melhor',
          70,
        ),
        isA<PieceProgressState>().having(
          (s) => s['001']?.bestScore,
          'melhor',
          80,
        ),
      ],
    );

    blocTest<PieceProgressCubit, PieceProgressState>(
      'a mesma escolha de transposição não emite nada',
      build: () => PieceProgressCubit(prefs: prefs),
      act: (c) async {
        await c.setTranspose('001', null);
      },
      expect: () => <PieceProgressState>[],
    );

    blocTest<PieceProgressCubit, PieceProgressState>(
      'carregar outra biblioteca troca o id e o mapa',
      setUp: () async {
        await prefs.setString('lib_progress_a', '{"1":{"s":70}}');
      },
      build: () => PieceProgressCubit(prefs: prefs),
      act: (c) => c.load('a'),
      expect: () => [
        isA<PieceProgressState>()
            .having((s) => s.libraryId, 'biblioteca', 'a')
            .having((s) => s['1']?.bestScore, 'melhor', 70),
      ],
    );

    blocTest<PieceProgressCubit, PieceProgressState>(
      'o progresso gravado volta com um cubit novo',
      build: () => PieceProgressCubit(prefs: prefs, now: () => agora),
      act: (c) async {
        await c.markOpened('001', transpose: '-m3');
        await c.recordScore('001', 90);
      },
      verify: (c) async {
        final again = PieceProgressCubit(prefs: prefs);
        await again.load('hinos');
        expect(again.state['001']?.bestScore, 90);
        expect(again.state['001']?.transpose, '-m3');
        expect(again.state.lastOpenedId, '001');
        await again.close();
      },
    );
  });
}
