import 'dart:ui';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny_comum/render/score_size_log.dart';
import 'package:zywny_diag/diag_log.dart';

/// Um documento de uma página 1000×1400 sem notas: o bastante para medir.
VsbDocument _doc() {
  final page = ScenePage(
    index: 0,
    width: 1000,
    height: 1400,
    contentHeight: 1400,
    viewBoxFactor: 1,
    viewBox: const Rect.fromLTWH(0, 0, 1000, 1400),
    baseWidth: 1000,
    baseHeight: 1400,
    userScaleX: 1,
    userScaleY: 1,
    widthPx: 1000,
    heightPx: 1400,
    fit: const PageFit(scale: 1, tx: 0, ty: 0),
    origin: Offset.zero,
    root: SceneNode(className: 'page', hidden: false, children: []),
    elements: [],
    byId: {},
  );
  return VsbDocument(
    manifest: const VsbManifest(
      format: 'vsb',
      version: 1,
      generator: 'test',
      pageCount: 1,
      files: VsbManifestFiles(scene: 'scene.json', glyphs: 'glyphs.json'),
    ),
    glyphs: const {},
    pages: [page],
  );
}

void main() {
  late MemoryDiagStorage store;

  setUp(() async {
    store = MemoryDiagStorage();
    await DiagLog.init(storage: store, installHandlers: false);
  });
  tearDown(DiagLog.reset);

  // Quantas linhas `ZYWNY_TAMANHO` o log já tem.
  int linhas() => 'ZYWNY_TAMANHO'.allMatches(store.read('app')).length;

  group('ScoreSizeState', () {
    test('é igual pelo valor e pelo documento', () {
      final doc = _doc();
      expect(
        ScoreSizeState(doc: doc, box: const Size(800, 600)),
        ScoreSizeState(doc: doc, box: const Size(800, 600)),
      );
      expect(
        ScoreSizeState(doc: doc, box: const Size(800, 600)),
        isNot(ScoreSizeState(doc: _doc(), box: const Size(800, 600))),
      );
    });
  });

  group('ScoreSizeCubit', () {
    blocTest<ScoreSizeCubit, ScoreSizeState>(
      'a primeira medição vira o estado',
      build: ScoreSizeCubit.new,
      act: (cubit) => cubit.medir(
        label: 'hino 001',
        doc: _doc(),
        box: const Size(800, 600),
        dpr: 2,
        continuous: false,
      ),
      expect: () => [
        isA<ScoreSizeState>().having(
          (s) => s.box,
          'caixa',
          const Size(800, 600),
        ),
      ],
    );

    test('grava uma linha na primeira medição', () {
      final cubit = ScoreSizeCubit();
      addTearDown(cubit.close);

      cubit.medir(
        label: 'hino 001',
        doc: _doc(),
        box: const Size(800, 600),
        dpr: 2,
        continuous: false,
      );

      expect(linhas(), 1);
      expect(store.read('app'), contains('ZYWNY_TAMANHO hino 001'));
    });

    test('a mesma partitura na mesma caixa não grava de novo', () {
      final cubit = ScoreSizeCubit();
      addTearDown(cubit.close);
      final doc = _doc();

      for (var i = 0; i < 3; i++) {
        cubit.medir(
          label: 'hino 001',
          doc: doc,
          box: const Size(800, 600),
          dpr: 2,
          continuous: false,
        );
      }

      expect(linhas(), 1);
    });

    test('outra caixa grava de novo', () {
      final cubit = ScoreSizeCubit();
      addTearDown(cubit.close);
      final doc = _doc();

      cubit.medir(
        label: 'hino 001',
        doc: doc,
        box: const Size(800, 600),
        dpr: 2,
        continuous: false,
      );
      cubit.medir(
        label: 'hino 001',
        doc: doc,
        box: const Size(400, 600),
        dpr: 2,
        continuous: false,
      );

      expect(linhas(), 2);
    });

    test('outra partitura (outro documento) grava de novo', () {
      final cubit = ScoreSizeCubit();
      addTearDown(cubit.close);

      cubit.medir(
        label: 'hino 001',
        doc: _doc(),
        box: const Size(800, 600),
        dpr: 2,
        continuous: false,
      );
      cubit.medir(
        label: 'hino 002',
        doc: _doc(),
        box: const Size(800, 600),
        dpr: 2,
        continuous: false,
      );

      expect(linhas(), 2);
    });

    test('caixa sem tamanho finito não grava nem muda o estado', () {
      final cubit = ScoreSizeCubit();
      addTearDown(cubit.close);

      cubit.medir(
        label: 'hino 001',
        doc: _doc(),
        box: const Size(double.infinity, 600),
        dpr: 2,
        continuous: false,
      );

      expect(linhas(), 0);
      expect(cubit.state.box, isNull);
    });

    test('só o pixel por ponto mudar não grava de novo', () {
      final cubit = ScoreSizeCubit();
      addTearDown(cubit.close);
      final doc = _doc();

      cubit.medir(
        label: 'hino 001',
        doc: doc,
        box: const Size(800, 600),
        dpr: 2,
        continuous: false,
      );
      cubit.medir(
        label: 'hino 001',
        doc: doc,
        box: const Size(800, 600),
        dpr: 3,
        continuous: false,
      );

      expect(linhas(), 1);
    });
  });
}
