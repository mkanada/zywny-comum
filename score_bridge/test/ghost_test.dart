// Nota fantasma (§10): a porta Dart tem de bater os vetores da referência
// Python (test/fixtures/fantasma/vetores.json): o `resumo` exatamente e os
// números com tolerância de 0,5 unidade de viewBox.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

const _dir = 'test/fixtures/fantasma';

void main() {
  final vectors = json.decode(
    File('$_dir/vetores.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (vectors['casos'] as List).cast<Map<String, dynamic>>();
  final docs = <String, VsbDocument>{};

  VsbDocument load(String name) => docs.putIfAbsent(
    name,
    () => VsbDocument.fromBytes(File('$_dir/$name').readAsBytesSync()),
  );

  test('pitchpos.json e geometria de pauta chegam ao modelo', () {
    final doc = load('satie.vsb');
    expect(doc.pitchPos, isNotNull);
    final note = doc.pitchPos!.events['orw55dt']!;
    expect(note.isNote, isTrue);
    expect(note.clefOffset, -2);
    expect(note.key, {'c': 1, 'f': 1});
    expect(note.loc, -3);
    final staff = doc.pages[0].byId['yy2zfkq']!.staffGeometry!;
    expect(staff.topY, 808);
    expect(staff.unit, 90);
    expect(staff.lines, 5);
  });

  test('fixtures antigas (sem pitchpos) não têm fantasma', () {
    final doc = VsbDocument.fromBytes(
      File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
    );
    expect(doc.pitchPos, isNull);
    expect(doc.ghostsFor(expectedIds: ['orw55dt'], wrongKeys: [60]), isEmpty);
  });

  for (final c in cases) {
    test(c['nome'] as String, () {
      final doc = load(c['vsb'] as String);
      final got = doc.ghostsFor(
        expectedIds: (c['esperados'] as List).cast<String>(),
        wrongKeys: (c['teclas'] as List).cast<int>(),
      );
      final resumo = (c['resumo'] as List).cast<Map<String, dynamic>>();
      expect(got.length, resumo.length);
      for (var i = 0; i < got.length; i++) {
        final g = got[i];
        final r = resumo[i];
        expect(g.loc, r['loc'], reason: 'loc');
        expect(g.octaveShift, r['m'], reason: 'm');
        expect(
          g.accidental?.glyphId.split(':').last,
          r['accid'],
          reason: 'acidente',
        );
        expect(g.ledgers.length, r['ledgers'], reason: 'linhas suplementares');
        expect(g.pname, r['pname']);
        expect(g.octave, r['oct']);
        expect(g.alter, r['alt']);
        expect(g.staffId, r['staff']);
        expect(g.targetId, r['target']);
      }
      final full = c['fantasmas'] as List?;
      if (full == null) return;
      for (var i = 0; i < got.length; i++) {
        final g = got[i];
        final w = full[i] as Map<String, dynamic>;
        void near(double a, num b, String what) =>
            expect(a, closeTo(b.toDouble(), 0.5), reason: what);
        final head = w['head'] as Map<String, dynamic>;
        expect(g.head.glyphId, head['g']);
        near(g.head.x, head['x'], 'head.x');
        near(g.head.y, head['y'], 'head.y');
        near(g.head.sx, head['sx'], 'head.sx');
        near(g.head.sy, head['sy'], 'head.sy');
        near(g.headWidth, w['width'], 'width');
        final acc = w['accid'] as Map<String, dynamic>?;
        expect(g.accidental == null, acc == null);
        if (acc != null) {
          expect(g.accidental!.glyphId, acc['g']);
          near(g.accidental!.x, acc['x'], 'accid.x');
          near(g.accidental!.y, acc['y'], 'accid.y');
        }
        final ledgers = (w['ledgers'] as List).cast<Map<String, dynamic>>();
        for (var j = 0; j < ledgers.length; j++) {
          near(g.ledgers[j].y, ledgers[j]['y'], 'ledger.y');
          near(g.ledgers[j].x1, ledgers[j]['x1'], 'ledger.x1');
          near(g.ledgers[j].x2, ledgers[j]['x2'], 'ledger.x2');
          near(g.ledgers[j].thickness, ledgers[j]['w'], 'ledger.w');
        }
        final oct = w['octave'] as Map<String, dynamic>?;
        expect(g.octaveMarker == null, oct == null);
        if (oct != null) {
          expect(g.octaveMarker!.glyphId, oct['g']);
          near(g.octaveMarker!.x, oct['x'], 'octave.x');
          near(g.octaveMarker!.y, oct['y'], 'octave.y');
        }
      }
    });
  }
}
