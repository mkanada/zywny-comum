import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/diag_log.dart';

/// Qual `.sf2` o motor de áudio carrega: o TimGM6mb embutido no app
/// (`assets/soundfonts/`), a não ser que o usuário tenha escolhido outro —
/// esse fica copiado no diretório de dados do app (o caminho devolvido pelo
/// seletor de arquivos, no Android, não sobrevive à sessão) e vale até ele
/// voltar ao padrão.
class SoundFontStore {
  const SoundFontStore();

  static const bundledAsset = 'assets/soundfonts/TimGM6mb.sf2';

  Future<File?> _customFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/custom.sf2');
    } catch (_) {
      // Sem path_provider (testes): só há o embutido.
      return null;
    }
  }

  Future<bool> hasCustom() async =>
      await (await _customFile())?.exists() ?? false;

  /// Bytes do `.sf2` a usar: o do usuário, se houver e for legível; senão o
  /// embutido.
  Future<Uint8List> load() async {
    final file = await _customFile();
    if (file != null && await file.exists()) {
      try {
        return await file.readAsBytes();
      } catch (e) {
        DiagLog.log(
          'erro',
          'soundfont do usuário ilegível, usando o padrão: $e',
        );
      }
    }
    final data = await rootBundle.load(bundledAsset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// Guarda [bytes] como o `.sf2` do usuário.
  Future<void> saveCustom(Uint8List bytes) async {
    final file = await _customFile();
    if (file == null) throw StateError('sem diretório de dados do app');
    await file.writeAsBytes(bytes, flush: true);
  }

  /// Volta ao `.sf2` embutido.
  Future<void> clearCustom() async {
    final file = await _customFile();
    if (file != null && await file.exists()) await file.delete();
  }
}
