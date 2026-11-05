// Compasso inteiro escondido (§11.2, regra 8, T17): a porta Dart tem de bater
// os 15 vetores `casosCompasso` da referência Python (hide_ref.py): o que
// some (notas, acordes, barras, traços, pausas de verdade, tercinas,
// ligaduras) e a pausa de compasso que entra no lugar, uma por pauta.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'hide_test.dart' show pageRefOf;

const _dir = 'test/fixtures/sumico';

void main() {
  final vectors = json.decode(
    File('$_dir/vetores.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (vectors['casosCompasso'] as List).cast<Map<String, dynamic>>();
  final tolerance = (vectors['tolerancia'] as num).toDouble();
  final docs = <String, VsbDocument>{};

  VsbDocument load(String name) => docs.putIfAbsent(
    name,
    () => VsbDocument.fromBytes(File('$_dir/$name').readAsBytesSync()),
  );

  test('são 15 casos', () => expect(cases, hasLength(15)));

  for (final c in cases) {
    test(c['nome'] as String, () {
      final doc = load(c['vsb'] as String);
      final page = pageRefOf(c['pagina']!);
      final measures = (c['compassos'] as List).cast<String>().toSet();
      final want = c['esperado'] as Map<String, dynamic>;
      final hidden = want['hidden'] as Map<String, dynamic>;
      final resumo = c['resumo'] as Map<String, dynamic>;

      final got = doc.hiddenShapesForMeasures(measures, page: page);
      expect(got.notes, (hidden['notes'] as List).cast<String>());
      expect(got.chords, (hidden['chords'] as List).cast<String>());
      final beams = (hidden['beams'] as List).cast<Map<String, dynamic>>();
      expect(got.beams.length, beams.length, reason: 'barras');
      for (var i = 0; i < beams.length; i++) {
        expect(got.beams[i].id, beams[i]['id']);
        expect(got.beams[i].shapes, beams[i]['shapes']);
      }
      final ledgers = (hidden['ledgers'] as List).cast<List<dynamic>>();
      expect(got.ledgers.length, ledgers.length, reason: 'traços');
      for (var i = 0; i < ledgers.length; i++) {
        final w = ledgers[i];
        expect(got.ledgers[i].staff, w[0]);
        expect(got.ledgers[i].side, w[1]);
        expect(got.ledgers[i].k, w[2]);
        expect(got.ledgers[i].x1, closeTo((w[3] as num).toDouble(), tolerance));
        expect(got.ledgers[i].x2, closeTo((w[4] as num).toDouble(), tolerance));
      }
      expect(
        got.rests,
        (hidden['rests'] as List).cast<String>(),
        reason: 'pausas',
      );
      expect(got.tuplets, (hidden['tuplets'] as List).cast<String>());
      expect(got.controls, (hidden['controls'] as List).cast<String>());

      final stand = [
        for (final m in measures.toList()..sort())
          ...doc.measureStandInsFor(m, page: page),
      ];
      final wantStand = (want['measureStandIn'] as List)
          .cast<Map<String, dynamic>>();
      expect(stand.length, wantStand.length, reason: 'pausas de compasso');
      for (var i = 0; i < wantStand.length; i++) {
        final w = wantStand[i];
        expect(stand[i].measureId, w['measure']);
        expect(stand[i].staffId, w['staff']);
        expect(stand[i].glyphId, w['g']);
        expect(stand[i].x, closeTo((w['x'] as num).toDouble(), tolerance));
        expect(stand[i].y, closeTo((w['y'] as num).toDouble(), tolerance));
        expect(stand[i].sx, closeTo((w['sx'] as num).toDouble(), 0.001));
        expect(stand[i].sy, closeTo((w['sy'] as num).toDouble(), 0.001));
        expect(stand[i].dots, isEmpty);
      }

      // O `resumo` à mão bate exatamente.
      expect(got.notes.length, resumo['notes']);
      expect(got.chords.length, resumo['chords']);
      expect(got.beams.length, resumo['beams']);
      expect(got.ledgers.length, resumo['ledgers']);
      expect(got.rests.length, resumo['rests']);
      expect(got.tuplets.length, resumo['tuplets']);
      expect(got.controls.length, resumo['controls']);
      expect(stand.length, resumo['standIns']);
    });
  }
}
