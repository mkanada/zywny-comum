import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:score_bridge/score_bridge.dart';
import 'package:web/web.dart' as web;

import 'score_renderer.dart';

ScoreRenderer createScoreRenderer() => WebScoreRenderer();

/// A resposta do `web/verovio_worker.js`.
extension type _WorkerReply(JSObject _) implements JSObject {
  external int get id;
  external bool get ok;
  external String? get json;
  external String? get error;
}

/// Verovio compilado para wasm (`tool/build_verovio_web.sh`) rodando num Web
/// Worker, para a página não travar. O worker devolve o `.vsb` na forma de
/// JSON único (`-t vsb-json`), que o `score_bridge` lê direto — sem zip.
class WebScoreRenderer implements ScoreRenderer {
  web.Worker? _worker;
  int _nextId = 0;
  final Map<int, Completer<String>> _pending = {};

  web.Worker _ensureWorker() {
    final existing = _worker;
    if (existing != null) return existing;
    final worker = web.Worker('verovio_worker.js'.toJS);
    worker.onmessage = ((web.MessageEvent event) {
      final reply = _WorkerReply(event.data as JSObject);
      final done = _pending.remove(reply.id);
      if (done == null) return;
      if (reply.ok) {
        done.complete(reply.json!);
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
  Future<RenderedScore> render(ScoreRenderRequest request) async {
    final worker = _ensureWorker();
    final id = _nextId++;
    final done = Completer<String>();
    _pending[id] = done;

    final options = <String, Object>{
      'pageWidth': request.pageWidth,
      'pageHeight': request.pageHeight,
      ...request.options,
    };
    final message = JSObject()
      ..setProperty('id'.toJS, id.toJS)
      ..setProperty('options'.toJS, jsonEncode(options).toJS)
      ..setProperty('bytes'.toJS, request.source.toJS);
    worker.postMessage(message);

    final json = await done.future;
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return RenderedScore(VsbDocument.fromJson(decoded));
  }
}
