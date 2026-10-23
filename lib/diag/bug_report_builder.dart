import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:zywny_diag/diag_log.dart';

/// Tudo o que vai no relatório de bug.
class BugReportInput {
  const BugReportInput({
    required this.appName,
    required this.appVersion,
    required this.at,
    required this.doing,
    required this.happened,
    required this.device,
    required this.routes,
    required this.stateJson,
    required this.logs,
    this.screenshotPng,
    this.attachments = const {},
  });

  /// `aprendizado`, `musicas`.
  final String appName;
  final String appVersion;
  final DateTime at;

  /// "O que eu estava fazendo" e "o que aconteceu", como o aluno escreveu.
  final String doing;
  final String happened;

  /// Aparelho, tela, idioma… (rótulo → valor).
  final Map<String, String> device;

  /// A pilha de telas, da primeira à de cima.
  final List<String> routes;

  /// `DiagLog.snapshotJson()`.
  final String stateJson;
  final List<DiagLogFile> logs;
  final Uint8List? screenshotPng;

  /// `DiagLog.attachments()`: nome → texto.
  final Map<String, String> attachments;
}

/// `zywny-bug-aprendizado-20261023-153012.zip`.
String bugReportFileName(String appName, DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${at.year}${two(at.month)}${two(at.day)}-'
      '${two(at.hour)}${two(at.minute)}${two(at.second)}';
  return 'zywny-bug-$appName-$stamp.zip';
}

/// O texto legível do relatório (`relatorio.txt`).
String bugReportText(BugReportInput r) {
  final sb = StringBuffer()
    ..writeln('Relatório de bug — zywny ${r.appName} ${r.appVersion}')
    ..writeln('Quando: ${r.at.toIso8601String()}')
    ..writeln()
    ..writeln('== O que eu estava fazendo ==')
    ..writeln(r.doing.trim().isEmpty ? '(não escreveu)' : r.doing.trim())
    ..writeln()
    ..writeln('== O que aconteceu ==')
    ..writeln(r.happened.trim().isEmpty ? '(não escreveu)' : r.happened.trim())
    ..writeln()
    ..writeln('== Aparelho e app ==');
  for (final e in r.device.entries) {
    sb.writeln('${e.key}: ${e.value}');
  }
  sb
    ..writeln()
    ..writeln('== Pilha de telas ==');
  if (r.routes.isEmpty) sb.writeln('(vazia)');
  for (var i = 0; i < r.routes.length; i++) {
    sb.writeln('${i + 1}. ${r.routes[i]}');
  }
  sb
    ..writeln()
    ..writeln('Os logs estão em logs/ (as últimas sessões e app.log), o estado')
    ..writeln('da tela no instante do relatório em estado.json e a imagem em')
    ..writeln('captura.png.');
  return sb.toString();
}

/// O `.zip` do relatório: `relatorio.txt`, `estado.json`, `captura.png`,
/// `anexos/*` e `logs/*.log`.
Uint8List buildBugReportZip(BugReportInput r) {
  final archive = Archive()
    ..add(ArchiveFile.string('relatorio.txt', bugReportText(r)))
    ..add(ArchiveFile.string('estado.json', r.stateJson));
  final shot = r.screenshotPng;
  if (shot != null) archive.add(ArchiveFile.bytes('captura.png', shot));
  for (final a in r.attachments.entries) {
    archive.add(ArchiveFile.string('anexos/${a.key}', a.value));
  }
  for (final f in r.logs) {
    archive.add(ArchiveFile.bytes('logs/${f.name}', utf8.encode(f.text)));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}
