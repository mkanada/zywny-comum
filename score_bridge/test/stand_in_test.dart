// Pausa substituta (§11, regras 4-7, L03): a porta Dart tem de bater os vetores
// da referência Python (test/fixtures/sumico/vetores.json, `esperado.standIn`):
// glifo, x, y, escala e pontos, com tolerância de 0,5 unidade de viewBox.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'hide_test.dart' show pageRefOf;

const _dir = 'test/fixtures/sumico';

void main() {
  final vectors =
      json.decode(File('$_dir/vetores.json').readAsStringSync())
          as Map<String, dynamic>;
  final cases = (vectors['casos'] as List).cast<Map<String, dynamic>>();
  final tolerance = (vectors['tolerancia'] as num).toDouble();
  final docs = <String, VsbDocument>{};

  VsbDocument load(String name) => docs.putIfAbsent(
    name,
    () => VsbDocument.fromBytes(File('$_dir/$name').readAsBytesSync()),
  );

  for (final c in cases) {
    test(c['nome'] as String, () {
      final doc = load(c['vsb'] as String);
      final want =
          (c['esperado'] as Map<String, dynamic>)['standIn']
              as Map<String, dynamic>;
      final got = doc.standInFor(
        (c['coluna'] as List).cast<String>(),
        page: pageRefOf(c['pagina']!),
      );
      expect(got, isNotNull);
      final rest = got!;
      void near(double a, Object b, String what) =>
          expect(a, closeTo((b as num).toDouble(), tolerance), reason: what);

      expect(rest.glyphId, want['glyph']);
      expect(rest.dur, want['dur']);
      expect(rest.loc, want['loc']);
      near(rest.x, want['x']!, 'x');
      near(rest.y, want['y']!, 'y');
      near(rest.sx, want['sx']!, 'sx');
      near(rest.sy, want['sy']!, 'sy');
      final dots = (want['dots'] as List).cast<Map<String, dynamic>>();
      expect(rest.dots.length, dots.length, reason: 'pontos');
      for (var i = 0; i < dots.length; i++) {
        near(rest.dots[i].cx, dots[i]['cx']!, 'cx');
        near(rest.dots[i].cy, dots[i]['cy']!, 'cy');
        near(rest.dots[i].rx, dots[i]['rx']!, 'rx');
        near(rest.dots[i].ry, dots[i]['ry']!, 'ry');
      }
      // O `resumo` à mão: o glifo e a `loc`.
      final resumo = c['resumo'] as Map<String, dynamic>;
      expect(rest.glyphId.split(':').last, resumo['rest']);
      expect(rest.loc, resumo['restLoc']);
      expect(rest.dots.length, resumo['dots']);
    });
  }

  test('sem a página: acha a página normal que contém a coluna', () {
    final doc = load('h010.vsb');
    final rest = doc.standInFor(['r10709ff', 'x1848jna', 'z1oagi0k']);
    expect(rest, isNotNull);
    expect(rest!.page, const PageRef(0));
    expect(rest.staffId, 'c1k2xsnz');
  });

  test('id expandido (-rend<N>) vale como o da cena', () {
    final doc = load('h010.vsb');
    final a = doc.standInFor(['r10709ff', 'x1848jna', 'z1oagi0k'])!;
    final b = doc.standInFor(['r10709ff-rend2', 'x1848jna', 'z1oagi0k'])!;
    expect(b.x, a.x);
    expect(b.y, a.y);
  });

  test('id que não existe, ou notas de pautas diferentes: null', () {
    final doc = load('h010.vsb');
    expect(doc.standInFor(['nao-existe']), isNull);
    expect(doc.standInFor(const []), isNull);
    // `r10709ff` (pauta c1k2xsnz) e `qyrisol` (pauta a1vokjmm).
    expect(doc.standInFor(['r10709ff', 'qyrisol']), isNull);
  });

  group('.vsb antigo ou sem a figura: null e nada quebra (critério 5)', () {
    test('sem pitchpos.json', () {
      final doc = VsbDocument.fromBytes(
        File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
      );
      expect(doc.pitchPos, isNull);
      expect(doc.standInFor(['orw55dt']), isNull);
    });

    test('pitchpos.json sem dur/dots é lido sem erro; sem pausa', () {
      // Um `.vsb` de antes de G08b não traz o campo: `dur` nulo, `dots` 0.
      final doc = load('h010.vsb');
      final event = doc.pitchPos!.events['r10709ff']!;
      expect(event.dur, 4);
      expect(event.dots, 0);
      final bare = VsbDocument(
        manifest: doc.manifest,
        glyphs: doc.glyphs,
        pages: doc.pages,
        timemap: doc.timemap,
        pitchPos: VsbPitchPos({
          for (final e in doc.pitchPos!.events.entries)
            e.key: PitchEvent(
              isNote: e.value.isNote,
              clefOffset: e.value.clefOffset,
              shift: e.value.shift,
              key: e.value.key,
              accidentals: e.value.accidentals,
              pname: e.value.pname,
              octave: e.value.octave,
              alter: e.value.alter,
              loc: e.value.loc,
            ),
        }),
      );
      expect(bare.pitchPos!.events['r10709ff']!.dur, isNull);
      expect(bare.pitchPos!.events['r10709ff']!.dots, 0);
      expect(bare.standInFor(['r10709ff']), isNull);
      // E esconder continua valendo: a coluna some do mesmo jeito.
      expect(
        bare.hiddenShapesFor({'r10709ff'}, page: const PageRef(0)).notes,
        ['r10709ff'],
      );
    });

    test('dicionário sem os glifos de pausa (lib antiga)', () {
      final doc = load('h010.vsb');
      final old = VsbDocument(
        manifest: doc.manifest,
        glyphs: {
          for (final e in doc.glyphs.entries)
            if (!e.key.contains(':E4E')) e.key: e.value,
        },
        pages: doc.pages,
        timemap: doc.timemap,
        pitchPos: doc.pitchPos,
      );
      expect(old.standInFor(['r10709ff', 'x1848jna', 'z1oagi0k']), isNull);
    });

    test('figura fora da faixa da regra 5 (dur 128)', () {
      final doc = load('h010.vsb');
      final events = Map.of(doc.pitchPos!.events);
      final base = events['r10709ff']!;
      events['r10709ff'] = PitchEvent(
        isNote: true,
        clefOffset: base.clefOffset,
        shift: base.shift,
        key: base.key,
        accidentals: base.accidentals,
        pname: base.pname,
        octave: base.octave,
        alter: base.alter,
        loc: base.loc,
        dur: 128,
      );
      final fast = VsbDocument(
        manifest: doc.manifest,
        glyphs: doc.glyphs,
        pages: doc.pages,
        timemap: doc.timemap,
        pitchPos: VsbPitchPos(events),
      );
      expect(fast.standInFor(['r10709ff']), isNull);
    });
  });
}
