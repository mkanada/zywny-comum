import 'dart:typed_data';

export 'library_blob_store_native.dart'
    if (dart.library.js_interop) 'library_blob_store_web.dart'
    show createLibraryBlobStore;

/// Onde os bytes de cada `.zywny` ficam, um por `id` de biblioteca. Só guarda
/// bytes: quem valida e quem lembra a lista e a biblioteca em uso é o
/// `LibraryStore`.
abstract interface class LibraryBlobStore {
  Future<bool> contains(String id);

  /// Os bytes de [id], ou `null` se não há.
  Future<Uint8List?> get(String id);

  /// Grava [bytes] por cima do que houver, sem deixar pacote pela metade.
  Future<void> put(String id, Uint8List bytes);

  Future<void> delete(String id);
}

/// Na memória, para os testes.
class MemoryLibraryBlobStore implements LibraryBlobStore {
  final Map<String, Uint8List> blobs = {};

  @override
  Future<bool> contains(String id) async => blobs.containsKey(id);

  @override
  Future<Uint8List?> get(String id) async => blobs[id];

  @override
  Future<void> put(String id, Uint8List bytes) async {
    blobs[id] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String id) async {
    blobs.remove(id);
  }
}
