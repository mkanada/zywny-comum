import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import '../ui/theme.dart';
import 'bug_report_delivery.dart';
import 'bug_report_form_cubit.dart';
import 'bug_report_sender.dart';

/// A tela do relatório de bug (ver `BugReportScope`): o aluno diz o que
/// fazia e o que aconteceu, e recebe o arquivo para enviar.
///
/// A tela de trás está parada (animações, som, metrônomo).
class BugReportPage extends StatefulWidget {
  const BugReportPage({
    super.key,
    required this.screenshot,
    required this.onCancel,
    required this.onSubmit,
    this.onSend,
  });

  /// A captura da tela como ela estava; `null` se não deu para tirar.
  final Uint8List? screenshot;

  /// Fecha sem gerar nada (a tela volta a andar).
  final VoidCallback onCancel;

  /// Gera o arquivo e o entrega.
  final Future<BugReportDelivery> Function(String doing, String happened)
  onSubmit;

  /// Envia o relatório à equipe; `null` quando este aparelho não envia (só o
  /// arquivo).
  final Future<BugReportReceipt> Function(String doing, String happened)?
  onSend;

  @override
  State<BugReportPage> createState() => _BugReportPageState();
}

/// Dona dos dois campos de texto (`TextEditingController`, objeto do framework);
/// o resto do estado do formulário é do [BugReportFormCubit].
class _BugReportPageState extends State<BugReportPage> {
  final _doing = TextEditingController();
  final _happened = TextEditingController();

  @override
  void dispose() {
    _doing.dispose();
    _happened.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        BugReportFormCubit(onSubmit: widget.onSubmit, onSend: widget.onSend),
    child: _BugReportView(
      doing: _doing,
      happened: _happened,
      screenshot: widget.screenshot,
      onCancel: widget.onCancel,
    ),
  );
}

/// A tela, com o formulário ([BugReportFormCubit]) acima dela.
class _BugReportView extends StatelessWidget {
  const _BugReportView({
    required this.doing,
    required this.happened,
    required this.screenshot,
    required this.onCancel,
  });

  final TextEditingController doing;
  final TextEditingController happened;
  final Uint8List? screenshot;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BugReportFormCubit, BugReportFormState>(
      builder: (context, form) => Scaffold(
        backgroundColor: kLibraryBg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: _filhos(context, form),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// O conteúdo da tela: o texto de apresentação, as perguntas (até o relatório
  /// ficar pronto ou enviado), o erro e o botão ou o resultado.
  List<Widget> _filhos(BuildContext context, BugReportFormState form) {
    final gerado = form.gerado;
    final enviado = form.enviado;
    final acabou = gerado != null || enviado != null;
    return [
      Text('Reportar um bug', style: serifDisplay(fontSize: 24)),
      const SizedBox(height: 4),
      const Text(
        'A tela, o som e o metrônomo estão parados. Conte o que '
        'aconteceu; o arquivo leva também uma imagem da tela e o '
        'registro dos últimos exercícios.',
        style: TextStyle(color: kInkCaption),
      ),
      const SizedBox(height: 12),
      if (!acabou) ...[
        if (screenshot != null) _screenshotPreview(),
        const SizedBox(height: 12),
        ..._questions(),
      ],
      const SizedBox(height: 16),
      if (form.erro != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(form.erro!, style: const TextStyle(color: kBadColor)),
        ),
      if (enviado != null)
        _Sent(receipt: enviado, onClose: onCancel)
      else if (gerado == null)
        _actions(context, form.ocupado)
      else
        _Done(delivery: gerado, onClose: onCancel),
    ];
  }

  /// A imagem da tela, pequena, para o aluno conferir o que vai no arquivo.
  Widget _screenshotPreview() => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 160),
    child: Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: kBorder)),
        child: Image.memory(screenshot!, fit: BoxFit.contain),
      ),
    ),
  );

  /// As duas perguntas do relatório: o que o aluno fazia e o que aconteceu.
  List<Widget> _questions() => [
    TextField(
      controller: doing,
      minLines: 2,
      maxLines: 5,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: 'O que você estava fazendo?',
        alignLabelWithHint: true,
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: happened,
      minLines: 2,
      maxLines: 5,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: 'O que aconteceu (o erro)?',
        alignLabelWithHint: true,
        border: OutlineInputBorder(),
      ),
    ),
  ];

  /// Cancelar, gerar o arquivo e (se o aparelho envia) enviar à equipe;
  /// tudo desligado enquanto um deles roda.
  Widget _actions(BuildContext context, bool ocupado) {
    final form = context.read<BugReportFormCubit>();
    final podeEnviar = form.podeEnviar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (podeEnviar) ...[
          const Text(
            'Enviar à equipe manda o texto acima, a imagem da tela e o '
            'registro do app para a equipe do zywny, que o lê para consertar o '
            'erro. Só a equipe vê. Ao apagar a conta, o que ainda não foi lido '
            'é apagado junto.',
            style: TextStyle(color: kInkCaption, fontSize: 13),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: ocupado ? null : onCancel,
              child: const Text('Cancelar'),
            ),
            if (podeEnviar)
              OutlinedButton(
                onPressed: ocupado
                    ? null
                    : () => unawaited(form.gerar(doing.text, happened.text)),
                child: Text(ocupado ? 'Aguarde…' : 'Só gerar o arquivo'),
              )
            else
              FilledButton(
                onPressed: ocupado
                    ? null
                    : () => unawaited(form.gerar(doing.text, happened.text)),
                child: Text(ocupado ? 'Gerando…' : 'Gerar relatório'),
              ),
            if (podeEnviar)
              FilledButton(
                onPressed: ocupado
                    ? null
                    : () => unawaited(form.enviar(doing.text, happened.text)),
                child: Text(ocupado ? 'Enviando…' : 'Enviar à equipe'),
              ),
          ],
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.delivery, required this.onClose});

  final BugReportDelivery delivery;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final where = delivery.savedAt;
    final name = where?.split('/').last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle, color: kGoodColor),
            SizedBox(width: 8),
            Text(
              'Relatório pronto',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          where == null
              ? 'O arquivo foi baixado pelo navegador (pasta de downloads). '
                    'Envie o arquivo zywny-bug-….zip.'
              : delivery.shared
              ? 'Escolha como enviar o arquivo $name na folha de '
                    'compartilhar. Se fechou sem querer, ele está em:'
              : 'Envie o arquivo $name. Ele está em:',
        ),
        if (where != null) ...[
          const SizedBox(height: 4),
          SelectableText(where, style: const TextStyle(color: kInkCaption)),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: onClose, child: const Text('Fechar')),
        ),
      ],
    );
  }
}

/// O relatório chegou à equipe.
class _Sent extends StatelessWidget {
  const _Sent({required this.receipt, required this.onClose});

  final BugReportReceipt receipt;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle, color: kGoodColor),
            SizedBox(width: 8),
            Text(
              'Relatório enviado',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Obrigado! A equipe lê os relatórios e abre um chamado para cada '
          'um. Se precisar citar este, o código é:',
        ),
        const SizedBox(height: 4),
        SelectableText(receipt.id, style: const TextStyle(color: kInkCaption)),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: onClose, child: const Text('Fechar')),
        ),
      ],
    );
  }
}
