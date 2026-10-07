import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Chrome/Edge/Opera têm `navigator.requestMIDIAccess`; Safari e iOS não.
/// (O Firefox até tem a função, mas recusa sem o add-on — isso aparece como
/// erro de permissão, não aqui.)
bool get webMidiSupported =>
    (web.window.navigator as JSObject).has('requestMIDIAccess');

/// `true` se o usuário já liberou o MIDI para este site — aí dá para listar os
/// teclados na abertura sem abrir pergunta nenhuma. Sem a Permissions API (ou
/// sem o nome `midi`), `false`: a pergunta fica para o clique.
Future<bool> webMidiGranted() async {
  try {
    // `package:web` não traz a Permissions API: chamada direta.
    final permissions =
        (web.window.navigator as JSObject)['permissions'] as JSObject?;
    if (permissions == null) return false;
    final descriptor = {'name': 'midi', 'sysex': false}.jsify();
    final status = await permissions
        .callMethod<JSPromise<JSObject>>('query'.toJS, descriptor)
        .toDart;
    return (status['state'] as JSString?)?.toDart == 'granted';
  } on Object {
    return false;
  }
}
