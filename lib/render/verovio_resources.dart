import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

const String _assetPath = 'assets/verovio_data.zip';

/// A file that only exists once extraction finished completely — an
/// interrupted/partial extraction must never be mistaken for a usable one,
/// since Verovio aborts on missing fonts instead of failing cleanly.
const String _markerRelativePath = 'text/LiberationSerif-Regular.ttf';

Future<String>? _resourcePathFuture;

/// Extracts (once per process) the Verovio engraving resources bundled with
/// the app and returns the directory holding them — pass it straight as the
/// Toolkit's `resourcePath`. Same tree as `verovio/data/` in the
/// `verovio_flutter_bridge` project (Bravura, Leipzig, Gootville,
/// Petaluma, Leland and `text/` with the Liberation TTFs and metrics).
///
/// Bundled as a single zip asset rather than raw files: Flutter's asset
/// bundler lists a directory entry non-recursively, so a plain
/// `assets/verovio_data/` folder would silently drop every SMuFL subfolder.
/// `Resources` only takes a real filesystem path (`SetPath`), so the zip has
/// to hit disk before the first render.
///
/// Regenerate the asset with `tool/build_verovio_assets.sh`.
Future<String> verovioResourcePath() {
  return _resourcePathFuture ??= _extractResources().catchError((Object e) {
    _resourcePathFuture = null;
    throw e;
  });
}

Future<String> _extractResources() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/verovio_data');
  final marker = File('${dir.path}/$_markerRelativePath');
  if (await marker.exists()) return dir.path;

  if (await dir.exists()) await dir.delete(recursive: true);
  await dir.create(recursive: true);

  final data = await rootBundle.load(_assetPath);
  final archive = ZipDecoder().decodeBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final out = File('${dir.path}/${file.name}');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(file.content as List<int>);
  }
  if (!await marker.exists()) {
    throw StateError(
      'assets/verovio_data.zip unpacked without $_markerRelativePath — '
      'regenerate it with tool/build_verovio_assets.sh',
    );
  }
  return dir.path;
}
