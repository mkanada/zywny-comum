// I12 — ler a pasta do rascunho na Web pela File System Access API.
//
// Chrome/Edge têm `window.showDirectoryPicker()`; Firefox e Safari não —
// lá o rascunho aceita um `.zip` da pasta, sem envelope (o instalador
// continua recusando pacote sem assinatura). O handle fica guardado na
// sessão: Recarregar relê os arquivos sem pedir a pasta de novo.
//
// Só Web (`dart:js_interop` + `package:web`): o `draft_folder.dart` importa
// isto por import condicional.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'course_files.dart';

/// A pasta tem o seletor de diretório? (Chrome/Edge; Firefox/Safari não.)
bool get webDirectoryPickerAvailable {
  try {
    return (web.window as JSObject).has('showDirectoryPicker');
  } on Object {
    return false;
  }
}

/// Pede a pasta ao usuário. `null` se cancelou ou sem suporte (aí vale o
/// `.zip`).
Future<WebDirectoryCourseFiles?> pickWebDirectory() async {
  if (!webDirectoryPickerAvailable) return null;
  try {
    final handle = await (web.window as JSObject)
        .callMethod<JSPromise<JSObject>>('showDirectoryPicker'.toJS)
        .toDart;
    final name = (handle['name'] as JSString?)?.toDart ?? 'pasta';
    return WebDirectoryCourseFiles(handle, label: name);
  } on Object {
    // Cancelou (AbortError) ou negou: sem rascunho, sem erro.
    return null;
  }
}

/// Os arquivos de uma pasta aberta pelo `showDirectoryPicker`. Guarda o
/// handle: Recarregar relê sem pedir a pasta de novo.
class WebDirectoryCourseFiles implements CourseFiles {
  WebDirectoryCourseFiles(JSObject handle, {String? label})
    : _handle = handle,
      label = label ?? _handleName(handle);

  final JSObject _handle;

  @override
  final String label;

  static String _handleName(JSObject handle) {
    try {
      return (handle['name'] as JSString?)?.toDart ?? 'pasta';
    } on Object {
      return 'pasta';
    }
  }

  @override
  Future<List<String>> list() async {
    final result = <String>[];
    await _collect(_handle, '', result);
    return result..sort();
  }

  Future<void> _collect(JSObject dir, String prefix, List<String> out) async {
    final iterator = dir.callMethod<JSObject>('values'.toJS);
    while (true) {
      final next = await (iterator.callMethod<JSPromise<JSObject>>('next'.toJS))
          .toDart;
      final done = (next['done'] as JSBoolean?)?.toDart ?? true;
      if (done) break;
      final entry = next['value'] as JSObject?;
      if (entry == null) continue;
      final kind = (entry['kind'] as JSString?)?.toDart;
      final name = (entry['name'] as JSString?)?.toDart ?? '';
      if (name.isEmpty || name.startsWith('.')) continue;
      if (kind == 'directory') {
        await _collect(entry, '$prefix$name/', out);
      } else {
        out.add('$prefix$name');
      }
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) throw ArgumentError('Arquivo ausente: $path');
    JSObject dir = _handle;
    for (var i = 0; i < parts.length - 1; i++) {
      dir = await dir
          .callMethod<JSPromise<JSObject>>(
            'getDirectoryHandle'.toJS,
            parts[i].toJS,
          )
          .toDart;
    }
    final fileHandle = await dir
        .callMethod<JSPromise<JSObject>>('getFileHandle'.toJS, parts.last.toJS)
        .toDart;
    final file = await fileHandle
        .callMethod<JSPromise<JSObject>>('getFile'.toJS)
        .toDart;
    final buffer = await file
        .callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS)
        .toDart;
    return buffer.toDart.asUint8List();
  }
}
