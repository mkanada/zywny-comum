// Mede o tempo de parse (VsbDocument.fromBytes) de cada peça de um diretório
// de .vsb, 3 execuções por peça, reportando a mediana. Insumo de R01
// (critério de aceite 5) e de uma eventual decisão sobre encoding binário.
//
// Precisa de dart:ui (VsbDocument usa Offset/Rect), então roda sob o Flutter
// Tester, não o Dart SDK puro:
//   flutter test tool/measure_parse_time.dart
// Diretório dos .vsb configurável por variável de ambiente (main() é chamado
// sem argumentos pelo runner de teste):
//   CORPUS_DIR=../compare/out/s08 flutter test tool/measure_parse_time.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:score_bridge/score_bridge.dart';

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

void main() {
  final dir = Directory(
    Platform.environment['CORPUS_DIR'] ?? '../compare/out/s08',
  );
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.vsb'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    stderr.writeln('nenhum .vsb encontrado em ${dir.path}');
    exitCode = 1;
    return;
  }

  print(
    '${'peça'.padRight(50)}${'bytes'.padLeft(10)}${'medianaMs'.padLeft(12)}',
  );
  for (final file in files) {
    final bytes = file.readAsBytesSync();
    final samples = <double>[];
    for (var run = 0; run < 3; run++) {
      final sw = Stopwatch()..start();
      VsbDocument.fromBytes(bytes);
      sw.stop();
      samples.add(sw.elapsedMicroseconds / 1000.0);
    }
    final name = file.uri.pathSegments.last;
    print(
      '${name.padRight(50)}${bytes.length.toString().padLeft(10)}'
      '${_median(samples).toStringAsFixed(2).padLeft(12)}',
    );
  }
}
