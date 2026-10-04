// J01 — Medição dos 600 hinos (critério 7, manual).
//
// Roda fora do `just test`: é lento (um render Verovio por hino).
//
//   TRAIL_STATS=1 flutter test test/trail_stats_manual_test.dart
//
// Imprime por hino: ocorrências, compassos lógicos, contíguo ou não,
// saltos, incompletos (grudados) e etapas do plano (J08). O resumo vai
// para as notas do J01/J08.
@Tags(['manual'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/hymn_package.dart';

import 'package:score_bridge/score_bridge.dart';
import 'package:zywny/music/performance_track.dart';
import 'package:zywny/trail/trail_path.dart';
import 'package:zywny/trail/trail_plan.dart';
import 'package:zywny/verovio_render.dart';

const _submodule = '/home/mauricio/rust_projects/verovio_flutter_bridge';
const _libPath = '$_submodule/verovio/bindings/dart/libverovio.so';
const _resourcePath = '$_submodule/verovio/data';

void main() {
  final runStats = Platform.environment['TRAIL_STATS'] == '1';
  test(
    'mede os 600 hinos',
    skip: !runStats ? 'só com TRAIL_STATS=1' : null,
    timeout: const Timeout(Duration(minutes: 30)),
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final missing = [_libPath, _resourcePath]
          .where((p) => !File(p).existsSync() && !Directory(p).existsSync())
          .toList();
      if (missing.isNotEmpty) {
        markTestSkipped('artefatos ausentes: ${missing.join(', ')}');
        return;
      }
      final hymns = await openLocalHymnPackage();
      if (hymns == null) {
        markTestSkipped('sem dist/hinos.zywny e keys/ (just pacote-hinos)');
        return;
      }
      final files = hymns.pieces;
      expect(files, hasLength(600));

      final tmp = await Directory.systemTemp.createTemp('trail_stats');
      addTearDown(() => tmp.delete(recursive: true));

      var contiguous = 0;
      var withJumps = 0;
      var withIncomplete = 0;
      var anacrusis = 0;
      var split = 0;
      var failures = 0;
      var noTrail = 0;
      var stavesOther = 0;
      final jumpKinds = <String, int>{};

      for (final f in files) {
        final name = f.id;
        try {
          final xml = await hymns.loadScore(f.id);
          final input = File('${tmp.path}/$name.musicxml');
          await input.writeAsBytes(xml, flush: true);
          final out = '${tmp.path}/$name.vsb';
          final doc = await renderScoreToVsb(
            VsbRenderRequest(
              inputPath: input.path,
              outputPath: out,
              libraryPath: File(_libPath).absolute.path,
              resourcePath: Directory(_resourcePath).absolute.path,
              pageWidth: kFallbackPageWidth,
              pageHeight: kFallbackPageHeight,
            ),
          );
          final tl = ScoreTimeline(doc);
          final path = TrailPath.fromTimeline(tl);
          final glued = [
            for (var i = 0; i < path.logical.length; i++)
              if (path.logical[i].measures.length > 1) i + 1,
          ];
          if (path.isContiguous) {
            contiguous++;
          } else {
            withJumps++;
            final key = path.jumps.length.toString();
            jumpKinds[key] = (jumpKinds[key] ?? 0) + 1;
          }
          if (glued.isNotEmpty) {
            withIncomplete++;
            if (glued.first == 1) anacrusis++;
            if (glued.any((n) => n != 1)) split++;
          }
          final track = PerformanceTrack.fromDocument(doc);
          final stavesOk = track.staves.contains(1) && track.staves.contains(2);
          if (!stavesOk) stavesOther++;
          final plan = TrailPlan.build(path, track, n: 5);
          if (plan.stages.isEmpty) noTrail++;
          // ignore: avoid_print
          print(
            '$name: occ=${tl.measures.length} '
            'lógicos=${path.measureCount} '
            'contíguo=${path.isContiguous} '
            'saltos=${path.jumps} '
            'grudados=$glued '
            'etapas=${plan.stages.length} '
            'pautas=${track.staves.toList()..sort()}',
          );
          await File(out).delete().catchError((_) => File(out));
          await input.delete().catchError((_) => input);
        } catch (e) {
          failures++;
          // ignore: avoid_print
          print('$name: ERRO $e');
        }
      }
      // ignore: avoid_print
      print(
        'TOTAIS hinos=${files.length} contíguos=$contiguous '
        'comSalto=$withJumps falhas=$failures semTrilha=$noTrail '
        'comIncompleto=$withIncomplete anacruse=$anacrusis '
        'partido=$split pautasEstranhas=$stavesOther '
        'saltosPorHino=$jumpKinds',
      );
    },
  );
}
