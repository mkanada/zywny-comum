import 'dart:io';
import 'dart:typed_data';

import 'score_music_reader.dart';
import 'verovio_paths.dart';
import 'verovio_render.dart';
import 'verovio_resources.dart';

ScoreMusicReader createScoreMusicReader() => NativeScoreMusicReader();

/// O caminho de sempre: grava a partitura num diretório temporário e pede o
/// retrato ao `libverovio` por FFI, num isolate (`readScoreMusic`).
class NativeScoreMusicReader implements ScoreMusicReader {
  @override
  Future<MusicSnapshotResult> read(
    Uint8List source, {
    required String fileName,
    Map<String, Object> options = const {},
  }) async {
    final tmpDir = await Directory.systemTemp.createTemp('zywny_music');
    try {
      final inputPath = '${tmpDir.path}/${_safeName(fileName)}';
      await File(inputPath).writeAsBytes(source, flush: true);
      return await readScoreMusic(
        inputPath: inputPath,
        libraryPath: findVerovioLibrary(),
        resourcePath: await verovioResourcePath(),
        options: options,
      );
    } finally {
      // O retrato já está todo na memória: o diretório pode ir.
      await tmpDir.delete(recursive: true);
    }
  }
}

String _safeName(String name) {
  final clean = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return clean.isEmpty ? 'score.musicxml' : clean;
}
