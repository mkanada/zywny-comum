import 'dart:typed_data';

import 'music_snapshot_result.dart';

export 'music_snapshot_result.dart';

import 'score_music_reader_web.dart'
    if (dart.library.io) 'score_music_reader_native.dart'
    as impl;

/// Lê o retrato do Verovio de uma partitura (T18, LP01): o bridge e os
/// atributos que o medidor do `zywny-aprendizado` lê. Não mexe na
/// `ScoreRenderer`, porque há muitas implementações falsas nos testes dos dois
/// apps. Duas implementações, escolhidas por import condicional: nativa (FFI,
/// num isolate) e Web (o worker, LP02).
abstract class ScoreMusicReader {
  /// [source] são os bytes da partitura (MusicXML, MEI ou `.mxl`) e [options] as
  /// opções do Verovio (`xmlIdSeed`, `transpose`), as mesmas do desenho.
  Future<MusicSnapshotResult> read(
    Uint8List source, {
    required String fileName,
    Map<String, Object> options = const {},
  });
}

ScoreMusicReader createScoreMusicReader() => impl.createScoreMusicReader();
