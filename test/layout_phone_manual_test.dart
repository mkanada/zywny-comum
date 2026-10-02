// U10 (parte 3) — Medição do layout do celular: quantas páginas e quantos
// compassos por página cabem em cada `unit`, e qual a altura do pentagrama em
// dp. Insumo da decisão D-SISTEMAS (dois sistemas por página?).
//
// Roda fora do `just test` (um render Verovio por combinação):
//
//   LAYOUT_PHONE=1 flutter test test/layout_phone_manual_test.dart
//
// Imprime uma linha por (página, unit, hino) e, no fim, a tabela por
// (página, unit). `ADJUST=1` repete com `adjustPageHeight` (parte 2: as
// alturas das páginas e a contagem de páginas devem bater com as de antes).
@Tags(['manual'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/layout_options.dart';
import 'package:zywny/verovio_render.dart';

const _submodule = '/home/mauricio/rust_projects/verovio_flutter_bridge';
const _libPath = '$_submodule/verovio/bindings/dart/libverovio.so';
const _resourcePath = '$_submodule/verovio/data';

/// Páginas medidas: a do emulador (411×914 dp, dpr 2,625, caixa 2054×912) e
/// a de um aparelho de 360 dp de altura (1775×780).
const _pages = [(2054, 912, 2.625), (1775, 780, 2.625)];
const _units = [12.0, 11.0, 10.0, 9.0, 8.0];
const _hinos = ['001', '005', '100', '300', '457'];

/// Altura do pentagrama (4 espaços = 8 meios-espaços) em px da página.
double? _staffHeightPx(VsbDocument doc) {
  double? found;
  void walk(SceneChild c) {
    if (found != null || c is! SceneNode) return;
    final g = c.staffGeometry;
    if (g != null) {
      final page = doc.pages.first;
      found = 8 * g.unit * page.widthPx / page.viewBox.width;
      return;
    }
    c.children.forEach(walk);
  }

  walk(doc.pages.first.root);
  return found;
}

/// Sistemas (nós `system`) de cada página.
List<int> _systemsPerPage(VsbDocument doc) {
  int count(SceneChild c) {
    if (c is! SceneNode) return 0;
    var n = c.className == 'system' ? 1 : 0;
    for (final child in c.children) {
      n += count(child);
    }
    return n;
  }

  return [for (final p in doc.pages) count(p.root)];
}

void main() {
  final run = Platform.environment['LAYOUT_PHONE'] == '1';
  final adjust = Platform.environment['ADJUST'] == '1';
  test(
    'mede páginas, compassos por página e altura do pentagrama',
    skip: !run ? 'só com LAYOUT_PHONE=1' : null,
    timeout: const Timeout(Duration(minutes: 30)),
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final tmp = await Directory.systemTemp.createTemp('layout_phone');
      addTearDown(() => tmp.delete(recursive: true));
      final rows = <String>[];
      for (final (w, h, dpr) in _pages) {
        for (final unit in _units) {
          final perPageMins = <int>[];
          final perPageAvgs = <double>[];
          final staffDp = <double>[];
          for (final hino in _hinos) {
            final xml = gzip.decode(
              File('assets/hinos/$hino.musicxml.gz').readAsBytesSync(),
            );
            final input = File('${tmp.path}/$hino.musicxml')
              ..writeAsBytesSync(xml);
            final doc = await renderScoreToVsb(
              VsbRenderRequest(
                inputPath: input.path,
                outputPath: '${tmp.path}/$hino.vsb',
                libraryPath: File(_libPath).absolute.path,
                resourcePath: Directory(_resourcePath).absolute.path,
                pageWidth: w,
                pageHeight: h,
                options: layoutOptionsToSend({
                  ...initialLayoutValues(phone: true),
                  'unit': unit,
                  if (adjust) 'adjustPageHeight': true,
                }),
              ),
            );
            final byPage = <int, Set<String>>{};
            for (final m in ScoreTimeline(doc).measures) {
              (byPage[m.page] ??= {}).add(m.id);
            }
            final counts = [for (final s in byPage.values) s.length];
            final staff = _staffHeightPx(doc);
            final heights = {for (final p in doc.pages) p.heightPx};
            perPageMins.add(counts.reduce((a, b) => a < b ? a : b));
            perPageAvgs.add(counts.reduce((a, b) => a + b) / counts.length);
            if (staff != null) staffDp.add(staff / dpr);
            // ignore: avoid_print
            print(
              '$w×$h unit=$unit hino=$hino páginas=${doc.pages.length} '
              'compassos/página mín=${counts.reduce((a, b) => a < b ? a : b)} '
              'média=${(counts.reduce((a, b) => a + b) / counts.length).toStringAsFixed(1)} '
              'sistemas/página=${_systemsPerPage(doc)} '
              'pentagrama=${staff == null ? '?' : (staff / dpr).toStringAsFixed(1)} dp '
              'alturas=${heights.toList()..sort()} '
              'conteúdo=${[for (final p in doc.pages) p.contentHeight]}',
            );
          }
          final avg = perPageAvgs.reduce((a, b) => a + b) / perPageAvgs.length;
          final minAll = perPageMins.reduce((a, b) => a < b ? a : b);
          final staff = staffDp.isEmpty
              ? '?'
              : (staffDp.reduce((a, b) => a + b) / staffDp.length)
                    .toStringAsFixed(1);
          rows.add(
            '| $w×$h | $unit | $minAll | ${avg.toStringAsFixed(1)} | $staff |',
          );
        }
      }
      // ignore: avoid_print
      print(
        '\n| página | unit | compassos/pág (mín) | compassos/pág (média) '
        '| pentagrama (dp) |\n| --- | --- | --- | --- | --- |\n${rows.join('\n')}',
      );
    },
  );
}
