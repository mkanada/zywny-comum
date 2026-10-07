import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'library_blob_store.dart';

LibraryBlobStore createLibraryBlobStore() => IndexedDbLibraryBlobStore();

/// IndexedDB: banco `zywny`, store `bibliotecas`, chave = `id`, valor = os
/// bytes do pacote. (O `shared_preferences` da Web é localStorage, ~5 MB —
/// pouco para os 3 MB dos hinos mais o resto.)
class IndexedDbLibraryBlobStore implements LibraryBlobStore {
  IndexedDbLibraryBlobStore({this.dbName = 'zywny'});

  static const storeName = 'bibliotecas';

  final String dbName;
  Future<web.IDBDatabase>? _db;

  Future<web.IDBDatabase> _open() => _db ??= _openDb().catchError((Object e) {
    // Se abrir falhar, a próxima chamada tenta de novo.
    _db = null;
    throw e;
  });

  Future<web.IDBDatabase> _openDb() {
    final done = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(dbName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(storeName)) {
        db.createObjectStore(storeName);
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      done.complete(request.result as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event _) {
      done.completeError(
        StateError('IndexedDB não abriu: ${request.error?.message}'),
      );
    }).toJS;
    request.onblocked = ((web.Event _) {
      done.completeError(StateError('IndexedDB bloqueado por outra aba.'));
    }).toJS;
    return done.future;
  }

  /// Roda [action] numa transação e espera ela **terminar** (não só o pedido
  /// responder): é o `complete` que garante que o dado foi para o disco.
  Future<T?> _run<T>(
    String mode,
    web.IDBRequest Function(web.IDBObjectStore store) action,
    T Function(JSAny? result) read,
  ) async {
    final db = await _open();
    final tx = db.transaction(storeName.toJS, mode);
    final done = Completer<void>();
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onerror = ((web.Event _) {
      if (!done.isCompleted) {
        done.completeError(StateError('IndexedDB: ${tx.error?.message}'));
      }
    }).toJS;
    tx.onabort = ((web.Event _) {
      if (!done.isCompleted) {
        done.completeError(
          StateError('IndexedDB abortou: ${tx.error?.message}'),
        );
      }
    }).toJS;
    final request = action(tx.objectStore(storeName));
    await done.future;
    return read(request.result);
  }

  @override
  Future<bool> contains(String id) async =>
      await _run(
        'readonly',
        (s) => s.count(id.toJS),
        (r) => ((r as JSNumber?)?.toDartInt ?? 0) > 0,
      ) ??
      false;

  @override
  Future<Uint8List?> get(String id) => _run<Uint8List?>(
    'readonly',
    (s) => s.get(id.toJS),
    (r) => r == null || r.isUndefined ? null : (r as JSUint8Array).toDart,
  );

  @override
  Future<void> put(String id, Uint8List bytes) async {
    await _run<void>('readwrite', (s) => s.put(bytes.toJS, id.toJS), (_) {});
    unawaited(_askPersistence());
  }

  /// Pede ao navegador para não apagar o IndexedDB quando faltar espaço —
  /// sem isso, a biblioteca instalada pode sumir sozinha. O Chrome decide em
  /// silêncio (app instalado como PWA conta a favor); o Firefox pergunta, por
  /// isso o pedido vem só aqui, logo depois de a pessoa instalar um pacote.
  static Future<void> _askPersistence() async {
    try {
      final storage = web.window.navigator.storage;
      if ((await storage.persisted().toDart).toDart) return;
      await storage.persist().toDart;
    } catch (_) {
      // Sem a API (ou recusado): segue como armazenamento comum.
    }
  }

  @override
  Future<void> delete(String id) =>
      _run<void>('readwrite', (s) => s.delete(id.toJS), (_) {});
}
