// O formulário do relatório de bug: se está gerando ou enviando, o erro e o
// resultado (o arquivo gerado ou o código que a equipe deu). Os campos de
// texto ficam na tela (`BugReportPage`); o Cubit recebe o que foi escrito.

import 'package:zywny_bloc/zywny_bloc.dart';

import 'bug_report_delivery.dart';
import 'bug_report_sender.dart';

/// O formulário do relatório: ocupado, o erro e o resultado (um deles, no fim).
class BugReportFormState extends Equatable {
  const BugReportFormState({
    this.ocupado = false,
    this.erro,
    this.gerado,
    this.enviado,
  });

  /// Gerando ou enviando agora: os botões ficam desligados.
  final bool ocupado;

  /// O motivo da falha, em texto para o aluno.
  final String? erro;

  /// O arquivo gerado (e onde ele ficou).
  final BugReportDelivery? gerado;

  /// O código do relatório que a equipe recebeu.
  final BugReportReceipt? enviado;

  BugReportFormState copyWith({
    bool? ocupado,
    String? erro,
    bool limparErro = false,
    BugReportDelivery? gerado,
    BugReportReceipt? enviado,
  }) => BugReportFormState(
    ocupado: ocupado ?? this.ocupado,
    erro: limparErro ? null : (erro ?? this.erro),
    gerado: gerado ?? this.gerado,
    enviado: enviado ?? this.enviado,
  );

  @override
  List<Object?> get props => [ocupado, erro, gerado, enviado];
}

/// Gera o arquivo do relatório ou o envia à equipe. [onSubmit] e [onSend] vêm
/// do `BugReportScope` (por `BugReportPage`); os testes trocam por falsos.
class BugReportFormCubit extends Cubit<BugReportFormState> {
  BugReportFormCubit({required this.onSubmit, this.onSend})
    : super(const BugReportFormState());

  /// Gera o arquivo e o entrega (salvar ou compartilhar).
  final Future<BugReportDelivery> Function(String doing, String happened)
  onSubmit;

  /// Envia à equipe; `null` quando este aparelho não envia (só o arquivo).
  final Future<BugReportReceipt> Function(String doing, String happened)?
  onSend;

  /// Dá para enviar à equipe: o botão "Enviar à equipe" só aparece com `true`.
  bool get podeEnviar => onSend != null;

  /// Gera o arquivo. Uma falha vira o erro da tela, sem fechar nada.
  Future<void> gerar(String doing, String happened) async {
    emit(const BugReportFormState(ocupado: true));
    try {
      final gerado = await onSubmit(doing, happened);
      _terminar(BugReportFormState(gerado: gerado));
    } on Object catch (e) {
      _terminar(BugReportFormState(erro: 'Não consegui gerar o arquivo: $e'));
    }
  }

  /// Envia à equipe. A recusa (`BugReportSendException`) mostra o motivo; a
  /// falha de rede, uma mensagem genérica. Dá para tentar de novo.
  Future<void> enviar(String doing, String happened) async {
    emit(const BugReportFormState(ocupado: true));
    try {
      final enviado = await onSend!(doing, happened);
      _terminar(BugReportFormState(enviado: enviado));
    } on BugReportSendException catch (e) {
      _terminar(BugReportFormState(erro: e.message));
    } on Object {
      _terminar(
        const BugReportFormState(
          erro:
              'Não consegui enviar agora (sem rede?). Tente de novo ou '
              'gere o arquivo.',
        ),
      );
    }
  }

  // A tela pode ter saído durante a espera (o Cubit já fechado): não emite.
  void _terminar(BugReportFormState fim) {
    if (isClosed) return;
    emit(fim);
  }
}
