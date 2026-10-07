// B09 — Todas as partituras dos clássicos abrem no Verovio (o mesmo render do
// app) e têm trilha? Manual, fora do `just test`:
//
//   CLASSICS_DIR=~/IdeaProjects/zywny_classicos \
//     flutter test test/classics_batch_manual_test.dart
//
// Lê `<pasta>/xml/*.musicxml` (`tool/fetch_classics.py`) e grava
// `<pasta>/render.tsv`: ok/erro, tempo, compassos, pautas, saltos e etapas.
@Tags(['manual'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/music/performance_track.dart';
import 'package:zywny/trail/trail_path.dart';
import 'package:zywny/trail/trail_plan.dart';
import 'package:zywny/verovio_render.dart';

import 'support/render_helper.dart';

void main() {
  final dir = Platform.environment['CLASSICS_DIR'];
  test(
    'renderiza e monta a trilha de cada clássico',
    skip: dir == null ? 'só com CLASSICS_DIR=<pasta>' : null,
    timeout: const Timeout(Duration(minutes: 30)),
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final files =
          Directory('$dir/xml')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.musicxml'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      final tmp = await Directory.systemTemp.createTemp('classics');
      addTearDown(() => tmp.delete(recursive: true));
      final rows = <String>[
        'arquivo\tresultado\trender_ms\tocorrencias\tlogicos\tpautas\tsaltos\tetapas\terro',
      ];
      for (final f in files) {
        final name = f.uri.pathSegments.last.replaceAll('.musicxml', '');
        final watch = Stopwatch()..start();
        try {
          final doc = await renderScoreToVsb(
            VsbRenderRequest(
              inputPath: f.path,
              outputPath: '${tmp.path}/$name.vsb',
              libraryPath: File(kLibverovioPath).absolute.path,
              resourcePath: Directory(kVerovioDataPath).absolute.path,
              pageWidth: kFallbackPageWidth,
              pageHeight: kFallbackPageHeight,
            ),
          );
          final ms = watch.elapsedMilliseconds;
          final tl = ScoreTimeline(doc);
          final path = TrailPath.fromTimeline(tl);
          final track = PerformanceTrack.fromDocument(doc);
          final plan = TrailPlan.build(path, track, n: 5);
          final staves = (track.staves.toList()..sort()).join(',');
          rows.add(
            '$name\tok\t$ms\t${tl.measures.length}\t${path.measureCount}\t'
            '$staves\t${path.jumps.length}\t${plan.stages.length}\t',
          );
        } catch (e) {
          rows.add(
            '$name\tERRO\t${watch.elapsedMilliseconds}\t\t\t\t\t\t'
            '${'$e'.split('\n').first}',
          );
        }
      }
      File('$dir/render.tsv').writeAsStringSync('${rows.join('\n')}\n');
      final bad = rows.where((r) => r.contains('\tERRO\t')).length;
      // ignore: avoid_print
      print('${files.length} partituras, $bad com erro → $dir/render.tsv');
    },
  );
}
