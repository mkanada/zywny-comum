import 'dart:io';
import 'dart:typed_data';

import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'bug_report_delivery.dart';

/// Quantos relatórios antigos ficam no aparelho.
const int _keepReports = 5;

Future<BugReportDelivery> deliverBugReport(
  String fileName,
  Uint8List bytes,
) async {
  // No Android, a pasta externa do app: o `adb pull` alcança.
  var base = Platform.isAndroid ? await getExternalStorageDirectory() : null;
  base ??= await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/bugs')..createSync(recursive: true);
  final file = File('${dir.path}/$fileName')..writeAsBytesSync(bytes);
  _dropOld(dir);

  // No Android, também uma cópia em Downloads/Zywny, que o aluno acha no
  // gerenciador de arquivos sem cabo.
  final downloads = await _saveToDownloads(file);

  var shared = false;
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await SharePlus.instance.share(
        ShareParams(
          subject: fileName,
          files: [XFile(file.path, mimeType: 'application/zip')],
        ),
      );
      shared = true;
    } on Object {
      // Sem folha de compartilhar: o aluno ainda tem o caminho do arquivo.
    }
  }
  return BugReportDelivery(savedAt: downloads ?? file.path, shared: shared);
}

/// A pasta (dentro de Downloads) onde os relatórios ficam no Android.
const String _downloadsFolder = 'Zywny';

/// Copia o relatório para `Downloads/Zywny` pelo MediaStore. Devolve o
/// caminho visível ao aluno, ou `null` se não for Android ou se falhar (o
/// arquivo da pasta do app continua valendo).
Future<String?> _saveToDownloads(File file) async {
  if (!Platform.isAndroid) return null;
  try {
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = _downloadsFolder;
    final info = await MediaStore().saveFile(
      tempFilePath: file.path,
      dirType: DirType.download,
      dirName: DirName.download,
    );
    if (info == null) return null;
    return 'Download/$_downloadsFolder/${info.name}';
  } on Object {
    return null;
  }
}

void _dropOld(Directory dir) {
  try {
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files.take(files.length - _keepReports)) {
      f.deleteSync();
    }
  } on Object {
    // Limpeza é só conforto.
  }
}

String platformDescription() =>
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
