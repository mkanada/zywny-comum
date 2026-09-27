// Gera as evidências visuais de A05b em `docs/exemplos/` (frames PNG).
//
//   cd score_bridge && flutter test tool/generate_examples.dart
//
// Determinístico: o relógio é o do Flutter Tester (`pump` com durações) e o
// player usa `seek` para cair em cada instante. O roteiro exato (instantes)
// vai impresso e gravado em `docs/exemplos/*/roteiro.md`.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import '../test/support/render_helpers.dart';

const _out = '../docs/exemplos';
const _width = 900.0;

VsbDocument _load(String part) => corpusDoc(part)!;

Future<ByteData> _shot(WidgetTester tester, GlobalKey key, int w, int h) =>
    captureBytes(tester, key, w, h);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadScoreFonts();
  });

  testWidgets('destaque de notas em fases diferentes', (tester) async {
    const piece = 'Gymnopedie';
    final doc = _load(piece);
    final controller = ScoreController(document: doc);
    final page = doc.pages[0];
    final h = (_width * page.heightPx / page.widthPx).round();
    final key = await pumpAtSize(
      tester,
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: _width,
          child: ScorePageView(
            document: doc,
            pageIndex: 0,
            controller: controller,
          ),
        ),
      ),
      _width.round(),
      h,
    );
    final ids = animatableIdsFromTimemap(doc.timemap)
        .where((id) => doc.geometry.elementOf(id)?.className == 'note')
        .where((id) => doc.geometry.elementOf(id)!.page == 0)
        .take(12)
        .toList();
    final dir = '$_out/destaque-notas/$piece';
    // Cinco notas acesas em instantes escalonados, com curvas diferentes.
    controller.highlight(
      ids[0],
      attack: const Duration(milliseconds: 200),
      hold: const Duration(milliseconds: 600),
      release: const Duration(milliseconds: 800),
    );
    await tester.pump();
    final schedule = <(int, void Function())>[
      (
        300,
        () => controller.highlight(ids[3], release: const Duration(seconds: 2)),
      ),
      (
        300,
        () => controller.highlight(
          ids[5],
          color: const ui.Color(0xFF1565C0),
          attack: const Duration(milliseconds: 300),
          hold: const Duration(seconds: 1),
          release: const Duration(milliseconds: 600),
        ),
      ),
      (
        300,
        () => controller.highlight(
          ids[7],
          release: const Duration(milliseconds: 1500),
        ),
      ),
    ];
    final frames = <String>[];
    var t = 0;
    Future<void> snap(String label) async {
      final bytes = await _shot(tester, key, _width.round(), h);
      final crop = _cropAround(doc, ids.take(8).toList(), _width);
      await writePng(
        tester,
        _crop(bytes, _width.round(), crop),
        crop.width.round(),
        crop.height.round(),
        '$dir/frame-$label.png',
      );
      frames.add('$label (t = $t ms)');
    }

    await tester.pump(const Duration(milliseconds: 100));
    t += 100;
    await snap('1-t0100');
    for (final (dt, act) in schedule) {
      act();
      await tester.pump(Duration(milliseconds: dt));
      t += dt;
    }
    await snap('2-t0700');
    await tester.pump(const Duration(milliseconds: 400));
    t += 400;
    await snap('3-t1100');
    await tester.pump(const Duration(milliseconds: 600));
    t += 600;
    await snap('4-t1700');
    await tester.pump(const Duration(milliseconds: 1500));
    t += 1500;
    await snap('5-t3200');
    controller.clearAll();
    File('$dir/roteiro.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('''# Destaque de notas — $piece, página 1

Gerado por `flutter test tool/generate_examples.dart` (em `score_bridge/`).

Notas (ids do timemap na página 1): `${ids.take(8).join(', ')}`.

Roteiro (relógio simulado do Flutter Tester):

- t = 0: `highlight(ids[0], attack: 200 ms, hold: 600 ms, release: 800 ms)`
- t = 100 ms: frame 1
- t = 100 ms: `highlight(ids[3], release: 2 s)`; t = 400 ms:
  `highlight(ids[5], azul, attack: 300 ms, hold: 1 s, release: 600 ms)`;
  t = 700 ms: `highlight(ids[7], release: 1,5 s)`
- ${frames.join('\n- ')}

Cada frame é um recorte da região das notas; nenhuma nota "salta" — cada uma
tem a própria fase (attack, hold, release) ao mesmo tempo.
''');
    controller.dispose();
  });

  testWidgets('virada de página por haste, dirigida pelo player', (
    tester,
  ) async {
    const piece = 'Nocturne';
    final doc = _load(piece);
    final controller = ScoreController(document: doc);
    final vc = ScoreViewController();
    final player = ScorePlayer(
      document: doc,
      controller: controller,
      view: vc,
      release: const Duration(milliseconds: 600),
    );
    final page = doc.pages[0];
    final h = (_width * page.heightPx / page.widthPx).round();
    final key = await pumpAtSize(
      tester,
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: _width,
          height: h.toDouble(),
          child: ScoreView(
            document: doc,
            controller: controller,
            viewController: vc,
            curtain: player.curtain,
          ),
        ),
      ),
      _width.round(),
      h,
    );
    final ms = player.measures;
    final i = ms.indexWhere(
      (m) => m.page == 0 && ms[ms.indexOf(m) + 1].page == 1,
    );
    final m = ms[i];
    final next = ms[i + 1];
    final d = ((m.endMs - m.startMs) / 4).clamp(0, 1000).toDouble();
    final dir = '$_out/virada-pagina/$piece';
    final steps = <(String, double)>[
      ('1-repouso', m.startMs - 800),
      ('2-meio-da-entrada', m.startMs + d / 2),
      ('3-estacionada', (m.startMs + d + next.startMs) / 2),
      ('4-meio-da-conclusao', next.startMs + d / 2),
      ('5-repouso-seguinte', next.startMs + d + 800),
    ];
    final lines = <String>[];
    for (final (label, at) in steps) {
      player.seek(Duration(microseconds: (at * 1000).round()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final bytes = await _shot(tester, key, _width.round(), h);
      await writePng(tester, bytes, _width.round(), h, '$dir/frame-$label.png');
      lines.add(
        '$label: `seek(${at.round()} ms)` — haste '
        '${player.curtain.value == null ? "ausente" : "edgeX = ${player.curtain.value!.edgeX.toStringAsFixed(0)}"}, '
        'página ${vc.currentPage + 1}',
      );
    }
    File('$dir/roteiro.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('''# Virada de página por haste — $piece

Gerado por `flutter test tool/generate_examples.dart` (em `score_bridge/`).

Página 1 → 2; último compasso da página 1: `${m.id}` (${m.startMs}–${m.endMs} ms),
primeiro da página 2 começa em ${next.startMs} ms; `D = min(1 s, duração/4)` =
${d.round()} ms. Player com `release: 600 ms`, `ScoreView` com a haste azul
padrão (`barWidth` = 2 × noteheadBlack, teto 1 s).

Cada frame é `player.seek(t)` seguido de um quadro:

- ${lines.join('\n- ')}

Nos frames 2–4 as notas do compasso tocando estão destacadas em vermelho, à
direita da haste; à esquerda dela aparece a página seguinte.
''');
    controller.clearAll();
    player.dispose();
    controller.dispose();
  });

  testWidgets('haste nos saltos de repetição (E03b, D-SALTO)', (tester) async {
    const piece = 'MapleLeafRag';
    final doc = VsbDocument.fromBytes(
      File('test/fixtures/maple-leaf-rag.vsb').readAsBytesSync(),
    );
    final controller = ScoreController(document: doc);
    final vc = ScoreViewController();
    final player = ScorePlayer(
      document: doc,
      controller: controller,
      view: vc,
      release: const Duration(milliseconds: 600),
    );
    final page = doc.pages[0];
    final h = (_width * page.heightPx / page.widthPx).round();
    final key = await pumpAtSize(
      tester,
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: _width,
          height: h.toDouble(),
          child: ScoreView(
            document: doc,
            controller: controller,
            viewController: vc,
            curtain: player.curtain,
          ),
        ),
      ),
      _width.round(),
      h,
    );
    final ms = player.measures;
    final dir = '$_out/repeticao/$piece';
    final tl = player.timeline;

    // Repouso de verdade (sem nenhuma haste ativa, nem de outro salto perto
    // dali — a Maple Leaf Rag tem saltos encadeados) a partir de [start],
    // andando de [step] em [step] (para trás com step negativo).
    double restNear(double start, double step) {
      var t = start;
      for (var i = 0; i < 10; i++) {
        if (tl.curtainAt(
              t,
              maxSweep: vc.maxSweepDuration,
              barWidth: vc.barWidth,
            ) ==
            null) {
          return t;
        }
        t += step;
      }
      return t;
    }

    Future<List<String>> saltoFrames(String prefix, double jumpMs) async {
      final i = ms.indexWhere((m) => m.startMs == jumpMs);
      final m = ms[i - 1];
      final next = ms[i];
      final d = ((m.endMs - m.startMs) / 4).clamp(0, 1000).toDouble();
      final steps = <(String, double)>[
        ('1-repouso', restNear(m.startMs - 800, -200)),
        ('2-meio-da-entrada', m.startMs + d / 2),
        ('3-estacionada', (m.startMs + d + next.startMs) / 2),
        ('4-meio-da-conclusao', next.startMs + d / 2),
        ('5-repouso-seguinte', restNear(next.startMs + d + 800, 200)),
      ];
      final lines = <String>[
        '### $prefix: compasso `${m.id}` (página ${m.page + 1}) → '
            '`${next.id}` (página ${next.page + 1}), salto em ${jumpMs.round()} ms',
        '',
        '`D = min(1 s, duração/4)` = ${d.round()} ms.',
        '',
      ];
      for (final (label, at) in steps) {
        player.seek(Duration(microseconds: (at * 1000).round()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        final bytes = await _shot(tester, key, _width.round(), h);
        await writePng(
          tester,
          bytes,
          _width.round(),
          h,
          '$dir/frame-$prefix-$label.png',
        );
        lines.add(
          '- $label: `seek(${at.round()} ms)` — haste '
          '${player.curtain.value == null ? "ausente" : "edgeX = ${player.curtain.value!.edgeX.toStringAsFixed(0)}, destino página ${player.curtain.value!.targetPageIndex! + 1}"}, '
          'página corrente ${vc.currentPage + 1}',
        );
      }
      return lines;
    }

    // Medido com --xml-id-seed 42 (docs/plano/E03b, notas de execução):
    // 39900 ms = salto 34 → 19 (página 2 → 1, a única entre páginas não
    // adjacentes fora da última); 97500 ms = salto 67 → 52, da última
    // página (3) para a 2.
    final lines1 = await saltoFrames('salto1', 39900);
    final lines2 = await saltoFrames('salto2', 97500);
    File('$dir/roteiro.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('''# Haste nos saltos de repetição — $piece

Gerado por `flutter test tool/generate_examples.dart` (em `score_bridge/`).
D-SALTO (decisão do usuário em 2026-09-22): haste generalizada — a mesma
regra de A05b/E03a, com a página de destino do salto atrás da haste, em
vez de sempre a seguinte.

`test/fixtures/maple-leaf-rag.vsb` (`-x 42`), `ScorePlayer` com
`release: 600 ms`.

${lines1.join('\n')}

${lines2.join('\n')}

O quadro "estacionada" de cada salto mostra o compasso de destino já visível
à esquerda da haste, antes de a música chegar lá.
''');
    controller.clearAll();
    player.dispose();
    controller.dispose();
  });

  for (final piece in const [
    (name: 'MapleLeafRag', fixture: 'maple-leaf-rag.vsb'),
    (name: 'Mazurka', fixture: 'mazurka.vsb'),
  ]) {
    testWidgets(
      'páginas alternativas nos saltos de repetição (P04c) — ${piece.name}',
      (tester) async {
        await _repeticaoAlternativaExample(
          tester,
          piece.name,
          'test/fixtures/${piece.fixture}',
        );
      },
    );
  }
}

/// Gera `docs/exemplos/repeticao-alternativa/<piece>/`: os 6 quadros do
/// único salto que cruza página desta peça (P01c), com a página alternativa
/// atrás da haste (P04a/P04b) — e um quadro de comparação com
/// `useAlternates: false` (o comportamento de antes da fase P, E03b).
Future<void> _repeticaoAlternativaExample(
  WidgetTester tester,
  String piece,
  String fixturePath,
) async {
  final doc = VsbDocument.fromBytes(File(fixturePath).readAsBytesSync());
  final dir = '$_out/repeticao-alternativa/$piece';

  Future<
    ({
      GlobalKey key,
      int w,
      int h,
      ScorePlayer player,
      ScoreViewController vc,
      ScoreController controller,
    })
  >
  setup({required bool useAlternates}) async {
    final controller = ScoreController(document: doc);
    final vc = ScoreViewController();
    final player = ScorePlayer(
      document: doc,
      controller: controller,
      view: vc,
      release: const Duration(milliseconds: 600),
      useAlternates: useAlternates,
    );
    final page = doc.pages[0];
    final h = (_width * page.heightPx / page.widthPx).round();
    final key = await pumpAtSize(
      tester,
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: _width,
          height: h.toDouble(),
          child: ScoreView(
            document: doc,
            controller: controller,
            viewController: vc,
            curtain: player.curtain,
          ),
        ),
      ),
      _width.round(),
      h,
    );
    return (
      key: key,
      w: _width.round(),
      h: h,
      player: player,
      vc: vc,
      controller: controller,
    );
  }

  final active = await setup(useAlternates: true);
  final tl = active.player.timeline;

  // Repouso de verdade (sem nenhuma haste ativa nem de outro salto perto
  // dali — mesma cautela de `saltoFrames`/E03b acima).
  double restNear(double start, double step) {
    var t = start;
    for (var i = 0; i < 10; i++) {
      if (tl.curtainAt(
            t,
            maxSweep: active.vc.maxSweepDuration,
            barWidth: active.vc.barWidth,
          ) ==
          null) {
        return t;
      }
      t += step;
    }
    return t;
  }

  // O único salto desta peça que cruza para uma página alternativa (P01c):
  // a 1ª ocorrência cuja `view` é alternativa é exatamente o destino dele —
  // uma sequência alternativa, uma vez alcançada, dura até o fim da peça
  // (D-ALT-EXTENSAO), então não há um 2º "primeiro salto" a achar.
  final i = tl.measures.indexWhere((m) => m.view.isAlternate);
  expect(i, greaterThan(0), reason: '$piece devia ter 1 salto alternativo');
  final m = tl.measures[i - 1];
  final next = tl.measures[i];
  expect(next.view.isAlternate, isTrue);
  final sequence = next.view.sequence!;

  // Critério 2 de P04c: o compasso de chegada é o 1º da página de trás.
  expect(
    doc.alternates[sequence].pages[next.view.index].firstMeasureId,
    next.id,
  );

  final d = ((m.endMs - m.startMs) / 4).clamp(0, 1000).toDouble();
  final steps = <(String, double)>[
    ('1-repouso', restNear(m.startMs - 800, -200)),
    ('2-meio-da-entrada', m.startMs + d / 2),
    ('3-estacionada', (m.startMs + d + next.startMs) / 2),
    ('4-meio-da-conclusao', next.startMs + d / 2),
    ('5-repouso-na-alternativa', restNear(next.startMs + d + 800, 200)),
  ];
  final lines = <String>[];
  for (final (label, at) in steps) {
    active.player.seek(Duration(microseconds: (at * 1000).round()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final bytes = await _shot(tester, active.key, active.w, active.h);
    await writePng(tester, bytes, active.w, active.h, '$dir/frame-$label.png');
    lines.add(
      '- $label: `seek(${at.round()} ms)` — displayedPage '
      '${active.vc.displayedPage} — haste '
      '${active.player.curtain.value == null ? "ausente" : "edgeX = ${active.player.curtain.value!.edgeX.toStringAsFixed(0)}"}',
    );
  }

  // Quadro 6: uma nota da 2ª passagem acesa, já na alternativa — depois da
  // conclusão da haste (`next.startMs + d`), não durante ela (`displayedPage`
  // só muda na conclusão).
  final atNotaAcesa = next.startMs + d + 50;
  active.player.seek(Duration(microseconds: (atNotaAcesa * 1000).round()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  expect(active.vc.displayedPage, next.view, reason: 'critério 2 do quadro 6');
  final bytes6 = await _shot(tester, active.key, active.w, active.h);
  await writePng(
    tester,
    bytes6,
    active.w,
    active.h,
    '$dir/frame-6-nota-acesa.png',
  );
  lines.add(
    '- 6-nota-acesa: `seek(${atNotaAcesa.round()} ms)` — '
    'displayedPage ${active.vc.displayedPage}, nota `${next.noteIds.isEmpty ? next.id : next.noteIds.first}` '
    '(passagem ${next.pass}) acesa na alternativa',
  );

  // Quadro de comparação: o mesmo instante "estacionada", com
  // `useAlternates: false` — o comportamento de antes da fase P (E03b): a
  // haste revela a página **normal**, não a alternativa.
  final before = await setup(useAlternates: false);
  final atEstacionada = (m.startMs + d + next.startMs) / 2;
  before.player.seek(Duration(microseconds: (atEstacionada * 1000).round()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  final bytesBefore = await _shot(tester, before.key, before.w, before.h);
  await writePng(
    tester,
    bytesBefore,
    before.w,
    before.h,
    '$dir/frame-antes-3-estacionada.png',
  );
  lines.add(
    '- antes-3-estacionada (`useAlternates: false`, comparação com E03b): '
    '`seek(${atEstacionada.round()} ms)` — displayedPage '
    '${before.vc.displayedPage} (a página normal, não a alternativa)',
  );

  File('$dir/roteiro.md')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '''# Páginas alternativas nos saltos de repetição — $piece

Gerado por `flutter test tool/generate_examples.dart` (em `score_bridge/`).
P04a-P04c (fase P): no único salto desta peça que cruza página (P01c), a
vista não volta para a página normal de destino — mostra uma página
**alternativa**, redesenhada a partir do compasso de chegada
(`Toolkit::Select`, P02c), atrás da haste (D-SALTO/E03a generalizados a
`PageRef` em P04a).

Compasso `${m.id}` (${m.startMs.round()}–${m.endMs.round()} ms) → `${next.id}`
(sequência alternativa $sequence, página ${next.view.index}), salto em
${next.startMs.round()} ms. `D = min(1 s, duração/4)` = ${d.round()} ms.
`ScorePlayer` com `release: 600 ms`.

${lines.join('\n')}

O quadro "estacionada" mostra o compasso de chegada já visível à esquerda da
haste, no canto superior esquerdo da página alternativa — o 1º compasso
dela, por construção (P02c/P00). O quadro "antes" (`useAlternates: false`)
mostra a mesma haste revelando, em vez disso, a página normal de destino,
como antes desta fase.
''',
    );

  active.controller.clearAll();
  active.player.dispose();
  active.controller.dispose();
  before.controller.clearAll();
  before.player.dispose();
  before.controller.dispose();
}

/// Retângulo (px do frame) que cobre as notas [ids], com folga.
Rect _cropAround(VsbDocument doc, List<String> ids, double width) {
  Rect? r;
  for (final id in ids) {
    final rect = doc.geometry.rectForId(id, pageWidth: width)!;
    r = r == null ? rect : r.expandToInclude(rect);
  }
  final pad = 40.0;
  return Rect.fromLTRB(
    (r!.left - pad).clamp(0, width),
    (r.top - pad).clamp(0, double.infinity),
    (r.right + pad).clamp(0, width),
    r.bottom + pad,
  );
}

/// Recorta [bytes] (RGBA de largura [w]) em [crop].
ByteData _crop(ByteData bytes, int w, Rect crop) {
  final cw = crop.width.round();
  final ch = crop.height.round();
  final out = ByteData(cw * ch * 4);
  final x0 = crop.left.round();
  final y0 = crop.top.round();
  final rows = bytes.lengthInBytes ~/ 4 ~/ w;
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final sy = y0 + y;
      final sx = x0 + x;
      if (sy >= rows) continue;
      for (var c = 0; c < 4; c++) {
        out.setUint8(
          (y * cw + x) * 4 + c,
          bytes.getUint8((sy * w + sx) * 4 + c),
        );
      }
    }
  }
  return out;
}
