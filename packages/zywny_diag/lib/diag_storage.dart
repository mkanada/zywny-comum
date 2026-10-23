import 'dart:io';

/// Onde o [DiagLog] guarda as linhas, por chave (`app`, `s00007`…).
///
/// Síncrono de propósito: cada linha precisa estar no disco quando
/// [append] volta, para um travamento ou o app morto pelo sistema não
/// perder o final do log.
abstract class DiagStorage {
  /// As chaves que existem (inclusive as de execuções anteriores).
  List<String> keys();

  void append(String key, String line);

  /// O texto inteiro da chave, na ordem em que foi gravado (o trecho antigo
  /// que passou do limite primeiro, se ainda houver).
  String read(String key);

  void remove(String key);
}

/// Na memória: a Web (sem arquivo em disco) e os testes.
///
/// Cada chave guarda no máximo [maxLines] linhas; passando disso descarta as
/// mais antigas.
class MemoryDiagStorage implements DiagStorage {
  MemoryDiagStorage({this.maxLines = 40000});

  final int maxLines;
  final Map<String, List<String>> _lines = {};

  @override
  List<String> keys() => _lines.keys.toList();

  @override
  void append(String key, String line) {
    final lines = _lines.putIfAbsent(key, () => <String>[]);
    lines.add(line);
    // Descarta em blocos de um quarto, para não mexer na lista a cada linha.
    if (lines.length > maxLines + maxLines ~/ 4) {
      lines.removeRange(0, lines.length - maxLines);
    }
  }

  @override
  String read(String key) => (_lines[key] ?? const <String>[]).join();

  @override
  void remove(String key) => _lines.remove(key);
}

/// Em arquivos de uma pasta: `<chave>.log`, e `<chave>.1.log` quando o
/// arquivo passa de [maxBytes] (o trecho anterior; um terceiro não existe).
class FileDiagStorage implements DiagStorage {
  FileDiagStorage(this.dir, {this.maxBytes = 2 * 1024 * 1024}) {
    Directory(dir).createSync(recursive: true);
  }

  final String dir;
  final int maxBytes;
  final Map<String, RandomAccessFile> _open = {};
  final Map<String, int> _size = {};

  String _path(String key, {bool old = false}) =>
      '$dir/$key${old ? '.1' : ''}.log';

  @override
  List<String> keys() {
    final out = <String>[];
    for (final e in Directory(dir).listSync()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (!name.endsWith('.log') || name.endsWith('.1.log')) continue;
      out.add(name.substring(0, name.length - '.log'.length));
    }
    return out;
  }

  @override
  void append(String key, String line) {
    try {
      var f = _open[key];
      if (f == null) {
        final file = File(_path(key));
        f = file.openSync(mode: FileMode.append);
        _open[key] = f;
        _size[key] = file.lengthSync();
      }
      if ((_size[key] ?? 0) > maxBytes) {
        f.closeSync();
        File(_path(key)).renameSync(_path(key, old: true));
        f = File(_path(key)).openSync(mode: FileMode.append);
        _open[key] = f;
        _size[key] = 0;
      }
      f.writeStringSync(line);
      f.flushSync();
      _size[key] = (_size[key] ?? 0) + line.length;
    } catch (_) {
      // Log nunca pode derrubar o app.
    }
  }

  @override
  String read(String key) {
    final sb = StringBuffer();
    for (final old in [true, false]) {
      final f = File(_path(key, old: old));
      if (f.existsSync()) sb.write(f.readAsStringSync());
    }
    return sb.toString();
  }

  @override
  void remove(String key) {
    try {
      _open.remove(key)?.closeSync();
      _size.remove(key);
      for (final old in [true, false]) {
        final f = File(_path(key, old: old));
        if (f.existsSync()) f.deleteSync();
      }
    } catch (_) {}
  }
}
