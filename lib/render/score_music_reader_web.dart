import 'dart:typed_data';

import 'score_music_reader.dart';

ScoreMusicReader createScoreMusicReader() => _UnsupportedScoreMusicReader();

/// Ainda não há leitura do retrato na Web: o worker do Verovio ganha esse pedido
/// no LP02. Até lá, quem chama na Web recebe este erro explícito.
class _UnsupportedScoreMusicReader implements ScoreMusicReader {
  @override
  Future<MusicSnapshotResult> read(
    Uint8List source, {
    required String fileName,
    Map<String, Object> options = const {},
  }) {
    throw UnsupportedError('O retrato do Verovio na Web chega no LP02.');
  }
}
