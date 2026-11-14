import 'dart:typed_data';

/// O maior `.zip` que o envio à equipe aceita (4 MB). Acima disso o escopo
/// refaz o arquivo sem a captura da tela; se ainda passar, não envia.
const int kBugReportMaxUploadBytes = 4000000;

/// O que o aluno manda à equipe: o `.zip` do relatório e o texto dele.
class BugReportUpload {
  const BugReportUpload({
    required this.appName,
    required this.appVersion,
    required this.platform,
    required this.doing,
    required this.happened,
    required this.fileName,
    required this.zip,
  });

  /// `aprendizado`, `musicas`.
  final String appName;
  final String appVersion;

  /// Sistema operacional e navegador, em uma linha.
  final String platform;

  /// "O que eu estava fazendo" e "o que aconteceu", como o aluno escreveu.
  final String doing;
  final String happened;
  final String fileName;
  final Uint8List zip;
}

/// O recibo de um envio: o código que o aluno pode citar.
class BugReportReceipt {
  const BugReportReceipt(this.id);

  final String id;
}

/// O envio não foi aceito, por um motivo que o aluno entende (a mensagem vai
/// direto para a tela).
class BugReportSendException implements Exception {
  const BugReportSendException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Para onde o relatório vai quando o aluno escolhe **Enviar à equipe**.
///
/// O `zywny-comum` não sabe de Firebase nem de GitHub: o app entrega uma
/// implementação (o `aprendizado` grava no Firestore, e uma GitHub Action abre
/// a issue). Sem ela, o botão não aparece e fica só o arquivo.
abstract interface class BugReportSender {
  /// Há como enviar agora (conta conectada, Firebase ligado neste aparelho).
  /// Lido quando a tela do relatório abre.
  bool get isAvailable;

  /// Envia e devolve o recibo. Falha com [BugReportSendException] (motivo
  /// claro) ou outro erro (rede, regras).
  Future<BugReportReceipt> send(BugReportUpload upload);
}
