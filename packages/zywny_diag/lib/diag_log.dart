import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Registro de diagnóstico em arquivo, para testes em que o aparelho não
/// pode ficar ligado ao computador (teclado MIDI ocupando a porta USB).
///
/// Só grava no Android — no resto, [log] é um no-op. O arquivo fica no
/// diretório externo do app, legível pelo `adb` depois:
///
///     adb pull /sdcard/Android/data/com.example.zywny/files/diag.log
///
/// Cada linha é gravada e descarregada na hora (`flushSync`), então um
/// travamento ou o app morto pelo sistema não perde o final do log. Uma
/// execução nova não apaga a anterior: `diag.log` só é rotacionado para
/// `diag.1.log` quando passa de [_maxBytes].
class DiagLog {
  DiagLog._();

  static const _maxBytes = 8 * 1024 * 1024;
  static RandomAccessFile? _file;
  static final Stopwatch _clock = Stopwatch();

  /// Abre o arquivo e liga a captura de erros e do ciclo de vida do app.
  /// Chamar uma vez, logo depois de `WidgetsFlutterBinding.ensureInitialized`.
  static Future<void> init() async {
    // Só no Android; `Platform` nem pode ser consultada na Web.
    if (kIsWeb || !Platform.isAndroid || _file != null) return;
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final path = '${dir.path}/diag.log';
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        f.renameSync('${dir.path}/diag.1.log');
      }
      _file = await f.open(mode: FileMode.append);
    } catch (e) {
      debugPrint('DiagLog: não abriu o arquivo: $e');
      return;
    }
    _clock.start();
    log(
      'app',
      '==== nova execução ${DateTime.now().toIso8601String()} '
          '(${Platform.operatingSystemVersion}) ====',
    );

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      log(
        'erro',
        'FlutterError: ${details.exceptionAsString()}\n${details.stack}',
      );
      previousOnError?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      log('erro', 'não tratado: $error\n$stack');
      return false;
    };
    AppLifecycleListener(
      onStateChange: (s) => log('app', 'ciclo de vida: ${s.name}'),
    );
  }

  /// Uma linha: hora do relógio, ms desde a abertura do log, etiqueta e
  /// texto. Seguro de chamar antes de [init] ou fora do Android.
  static void log(String tag, String message) {
    final f = _file;
    if (f == null) return;
    final now = DateTime.now();
    final line =
        '${now.toIso8601String()} +${_clock.elapsedMilliseconds}ms '
        '[$tag] $message\n';
    try {
      f.writeStringSync(line);
      f.flushSync();
    } catch (_) {
      // Log nunca pode derrubar o app.
    }
  }
}
