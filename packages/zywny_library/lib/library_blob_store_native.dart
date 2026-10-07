import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'library_blob_store.dart';

LibraryBlobStore createLibraryBlobStore() => FileLibraryBlobStore();

/// Um arquivo por pacote: `<dados do app>/bibliotecas/<id>.zywny` (como o
/// `SoundFontStore` guarda o `.sf2`). [directory] existe para os testes.
class FileLibraryBlobStore implements LibraryBlobStore {
  FileLibraryBlobStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/bibliotecas');
  }

  Future<File> _file(String id) async =>
      File('${(await _directory()).path}/$id.zywny');

  @override
  Future<bool> contains(String id) async => (await _file(id)).exists();

  @override
  Future<Uint8List?> get(String id) async {
    final file = await _file(id);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> put(String id, Uint8List bytes) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    // Grava num temporário e renomeia: uma queda no meio não deixa um pacote
    // truncado no lugar do bom.
    final tmp = File('${dir.path}/$id.zywny.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename('${dir.path}/$id.zywny');
  }

  @override
  Future<void> delete(String id) async {
    final file = await _file(id);
    if (await file.exists()) await file.delete();
  }
}
