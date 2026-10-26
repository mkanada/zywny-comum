import 'dart:typed_data';

import 'bug_report_delivery_web.dart'
    if (dart.library.io) 'bug_report_delivery_native.dart'
    as impl;

/// O que a entrega do arquivo do relatório fez.
class BugReportDelivery {
  const BugReportDelivery({this.savedAt, this.shared = false});

  /// Onde o arquivo ficou no aparelho (`null` na Web: foi para Downloads).
  final String? savedAt;

  /// A folha de compartilhar do sistema foi aberta.
  final bool shared;
}

/// Entrega o arquivo do relatório ao aluno: guarda no aparelho e abre a folha
/// de compartilhar (Android, iOS), ou baixa pelo navegador (Web).
Future<BugReportDelivery> deliverBugReport(String fileName, Uint8List bytes) =>
    impl.deliverBugReport(fileName, bytes);

/// Sistema operacional e navegador, em uma linha, para o relatório.
String platformDescription() => impl.platformDescription();
