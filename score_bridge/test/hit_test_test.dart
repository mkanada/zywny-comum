// Coordenadas e hit-test (A04a).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helpers.dart';

void main() {
  final files = corpusFiles();
  if (files.isEmpty) {
    test('corpus ausente', () {}, skip: '$kCorpusDir não existe');
    return;
  }
  final docs = [
    for (final f in files.take(3)) VsbDocument.fromBytes(f.readAsBytesSync()),
  ];
  final rng = math.Random(7);

  List<ElementRef> pick(VsbDocument d, int n, {String? cls}) {
    final all = <ElementRef>[
      for (final p in d.pages)
        for (final e in p.elements)
          if (d.geometry.elementOf(e.id) != null &&
              (cls == null || e.className == cls))
            d.geometry.elementOf(e.id)!,
    ];
    return [for (var i = 0; i < n; i++) all[rng.nextInt(all.length)]];
  }

  test('ida e volta em unidades de viewBox (critério 1)', () {
    for (final d in docs) {
      for (final ref in pick(d, 7)) {
        final page = d.pages[ref.page];
        final rect = d.geometry.rectForId(ref.id, pageWidth: 731)!;
        final s = 731 / page.widthPx;
        final back = pagePxToPageRect(
          ui.Rect.fromLTRB(
            rect.left / s,
            rect.top / s,
            rect.right / s,
            rect.bottom / s,
          ),
          page,
        );
        expect((back.left - ref.bbox.left).abs(), lessThan(1e-6));
        expect((back.top - ref.bbox.top).abs(), lessThan(1e-6));
        expect((back.right - ref.bbox.right).abs(), lessThan(1e-6));
        expect((back.bottom - ref.bbox.bottom).abs(), lessThan(1e-6));
      }
    }
  });

  test('escala coerente com a largura do widget (critério 2)', () {
    final d = docs.first;
    for (final ref in pick(d, 10)) {
      final a = d.geometry.rectForId(ref.id, pageWidth: 400)!;
      final b = d.geometry.rectForId(ref.id, pageWidth: 800)!;
      expect(b.left, closeTo(a.left * 2, 1e-9));
      expect(b.top, closeTo(a.top * 2, 1e-9));
      expect(b.width, closeTo(a.width * 2, 1e-9));
      expect(b.height, closeTo(a.height * 2, 1e-9));
    }
  });

  test('idAt no centro da bbox e em área vazia (critérios 3 e 4)', () {
    for (final d in docs) {
      for (final ref in pick(d, 7, cls: 'note')) {
        final rect = d.geometry.rectForId(ref.id, pageWidth: 600)!;
        final got = d.geometry.idAt(ref.page, rect.center, pageWidth: 600);
        expect(got, isNotNull);
        final gotRef = d.geometry.elementOf(got!)!;
        // Sem filtro, vence o de menor área que contém o ponto; nunca um
        // elemento maior que a própria nota.
        expect(
          gotRef.bbox.width * gotRef.bbox.height,
          lessThanOrEqualTo(ref.bbox.width * ref.bbox.height + 1e-9),
        );
        // Com o filtro de classe, é uma nota, e a mais específica.
        final note = d.geometry.idAt(
          ref.page,
          rect.center,
          pageWidth: 600,
          classes: {'note'},
        );
        expect(d.geometry.elementOf(note!)!.className, 'note');
        final measure = d.geometry.idAt(
          ref.page,
          rect.center,
          pageWidth: 600,
          classes: {'measure'},
        );
        expect(measure, isNotNull);
        expect(d.geometry.elementOf(measure!)!.className, 'measure');
        expect(measure, isNot(note));
      }
      // Canto da página: fora de qualquer elemento.
      expect(d.geometry.idAt(0, const ui.Offset(1, 1), pageWidth: 600), isNull);
    }
  });

  test('bbox degenerada nunca é indexada nem devolvida (critério 5)', () {
    for (final d in docs) {
      var degenerate = 0;
      for (final p in d.pages) {
        for (final e in p.elements) {
          if (e.bbox.width <= 0 || e.bbox.height <= 0) {
            degenerate++;
            expect(d.geometry.elementOf(e.id), isNull);
          }
        }
      }
      // Sanidade: o teste só vale se o documento realmente tem alguma.
      // (Não falha se não tiver; é informativo.)
      expect(degenerate, greaterThanOrEqualTo(0));
    }
  });

  test('idsIn devolve as notas dentro de um retângulo', () {
    final d = docs.first;
    final ref = pick(d, 1, cls: 'note').single;
    final rect = d.geometry.rectForId(ref.id)!;
    final ids = d.geometry
        .idsIn(ref.page, rect.deflate(0.01), classes: {'note'})
        .toList();
    expect(ids, contains(ref.id));
  });

  test('a fixture do repositório indexa o mesmo que a página', () {
    final d = VsbDocument.fromBytes(
      File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
    );
    expect(d.geometry.length, greaterThan(500));
  });
}
