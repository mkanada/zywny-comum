import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'score_music_reader.dart';

ScoreMusicReader createScoreMusicReader() => WebScoreMusicReader();

/// A resposta do `web/verovio_worker.js` a um pedido `kind: 'music'`.
extension type _WorkerMusicReply(JSObject _) implements JSObject {
  external int get id;
  external bool get ok;
  external String? get bridge;
  external String? get attributes;
  external String? get error;
}

/// O retrato do Verovio na Web (T18, LP02): o mesmo `verovio_worker.js` do
/// desenho, com outro tipo de pedido (`kind: 'music'`). Tem um worker próprio:
/// o do `WebScoreRenderer` é privado dele, e um segundo worker custa só memória.
class WebScoreMusicReader implements ScoreMusicReader {
  web.Worker? _worker;
  int _nextId = 0;
  final Map<int, Completer<MusicSnapshotResult>> _pending = {};

  web.Worker _ensureWorker() {
    final existing = _worker;
    if (existing != null) return existing;
    final worker = web.Worker('verovio_worker.js'.toJS);
    worker.onmessage = ((web.MessageEvent event) {
      final reply = _WorkerMusicReply(event.data as JSObject);
      final done = _pending.remove(reply.id);
      if (done == null) return;
      if (reply.ok) {
        // Os atributos vêm como texto JSON do worker; o retrato é o mesmo
        // `{"bridge": …, "attributes": …}` que o nativo devolve.
        final attributes = jsonDecode(reply.attributes ?? '{}');
        done.complete(
          MusicSnapshotResult(
            jsonEncode({'bridge': reply.bridge, 'attributes': attributes}),
          ),
        );
      } else {
        done.completeError(StateError(reply.error ?? 'erro no worker'));
      }
    }).toJS;
    worker.onerror = ((web.Event event) {
      final pending = _pending.values.toList();
      _pending.clear();
      _worker?.terminate();
      _worker = null;
      for (final done in pending) {
        done.completeError(
          StateError('o worker do Verovio não carregou (verovio_worker.js)'),
        );
      }
    }).toJS;
    return _worker = worker;
  }

  @override
  Future<MusicSnapshotResult> read(
    Uint8List source, {
    required String fileName,
    Map<String, Object> options = const {},
  }) {
    final worker = _ensureWorker();
    final id = _nextId++;
    final done = Completer<MusicSnapshotResult>();
    _pending[id] = done;

    // O nome do arquivo não entra: o worker reconhece o zip pelos bytes, como
    // o Verovio. As opções são as da partitura desenhada (sem largura de página),
    // como no nativo, para que os ids batam.
    final message = JSObject()
      ..setProperty('kind'.toJS, 'music'.toJS)
      ..setProperty('id'.toJS, id.toJS)
      // `musicDerivation` (o MEI e o `music.json`) a Web ainda não atende: o
      // worker não tem esses pedidos, e o Verovio não conhece a opção.
      ..setProperty(
        'options'.toJS,
        jsonEncode({...options}..remove('musicDerivation')).toJS,
      )
      ..setProperty('bytes'.toJS, source.toJS);
    worker.postMessage(message);
    return done.future;
  }
}
