// J03 — TrailProgressCubit: o que é lido e gravado por hino, e o que avisa.
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_comum/trail/trail_progress.dart';
import 'package:zywny_comum/trail/trail_progress_cubit.dart';
import 'package:zywny_library/library_keys.dart';
import 'package:zywny_library/piece.dart' show kHymnsLibraryId;

const _full = TrailProgress(
  n: 5,
  total: 24,
  records: {'t0.notasD': StageRecord(state: StageState.aprovada, best: 95)},
);

/// Grava a trilha [progress] do hino [id] nas preferências, como uma
/// gravação anterior do app.
Future<void> _gravada(String id, TrailProgress progress) =>
    SharedPreferencesAsync().setString(
      trailKeyFor(kHymnsLibraryId, id),
      jsonEncode(progress.toJson()),
    );

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('TrailProgressState', () {
    test('copyWith troca só o campo pedido', () {
      const estado = TrailProgressState(byId: {'012': _full});

      expect(estado.copyWith(), estado);
      expect(estado.copyWith(libraryId: 'outra').libraryId, 'outra');
      expect(estado.copyWith(libraryId: 'outra').byId, estado.byId);
    });

    test('é igual pelo valor, até no mapa (Equatable)', () {
      expect(
        const TrailProgressState(byId: {'012': _full}),
        equals(const TrailProgressState(byId: {'012': _full})),
      );
      expect(
        const TrailProgressState(byId: {'012': _full}),
        isNot(equals(const TrailProgressState())),
      );
    });
  });

  group('TrailProgressCubit', () {
    test('começa sem trilha, na biblioteca dos hinos', () {
      final cubit = TrailProgressCubit();
      addTearDown(cubit.close);

      expect(cubit.state, const TrailProgressState());
      expect(cubit.libraryId, kHymnsLibraryId);
      expect(cubit['012'], TrailProgress.empty);
    });

    blocTest<TrailProgressCubit, TrailProgressState>(
      'save emite a trilha do hino e a grava',
      build: () => TrailProgressCubit(),
      act: (c) => c.save('012', _full),
      expect: () => [
        const TrailProgressState(byId: {'012': _full}),
      ],
      verify: (c) async {
        expect(
          await SharedPreferencesAsync().getString(
            trailKeyFor(kHymnsLibraryId, '012'),
          ),
          isNotNull,
        );
      },
    );

    blocTest<TrailProgressCubit, TrailProgressState>(
      'reset tira o hino e apaga a gravação',
      setUp: () => _gravada('012', _full),
      build: () => TrailProgressCubit(),
      seed: () => const TrailProgressState(byId: {'012': _full}),
      act: (c) => c.reset('012'),
      expect: () => [const TrailProgressState()],
      verify: (c) async {
        expect(
          await SharedPreferencesAsync().getString(
            trailKeyFor(kHymnsLibraryId, '012'),
          ),
          isNull,
        );
      },
    );

    blocTest<TrailProgressCubit, TrailProgressState>(
      'load lê só as trilhas gravadas e emite uma vez',
      setUp: () => _gravada('012', _full),
      build: () => TrailProgressCubit(),
      act: (c) => c.load(['012', '013']),
      expect: () => [
        const TrailProgressState(byId: {'012': _full}),
      ],
    );

    blocTest<TrailProgressCubit, TrailProgressState>(
      'loadMissing não relê o que já foi procurado',
      setUp: () => _gravada('013', _full),
      build: () => TrailProgressCubit(),
      act: (c) async {
        await c.load(['012']);
        await c.loadMissing(['012', '013']);
      },
      expect: () => [
        const TrailProgressState(),
        const TrailProgressState(byId: {'013': _full}),
      ],
    );

    test('summary dá o resumo da biblioteca sem montar o plano', () async {
      final cubit = TrailProgressCubit();
      addTearDown(cubit.close);
      await cubit.save('012', _full);

      final resumo = cubit.summary('012');
      expect(resumo.done, 1);
      expect(resumo.total, 24);
      expect(resumo.completed, isFalse);
      expect(cubit.summary('013').done, 0);
    });

    test(
      'se a tela fechar antes da trilha chegar, não emite nem lança',
      () async {
        final cubit = TrailProgressCubit();

        final carga = cubit.load(['012']);
        await cubit.close();

        await expectLater(carga, completes);
        expect(cubit.isClosed, isTrue);
        expect(cubit.state, const TrailProgressState());
      },
    );
  });
}
