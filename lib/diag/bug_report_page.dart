import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'bug_report_delivery.dart';

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
  });

  /// A captura da tela como ela estava; `null` se não deu para tirar.
  final Uint8List? screenshot;

  /// Fecha sem gerar nada (a tela volta a andar).
  final VoidCallback onCancel;

  /// Gera o arquivo e o entrega.
  final Future<BugReportDelivery> Function(String doing, String happened)
  onSubmit;

  @override
  State<BugReportPage> createState() => _BugReportPageState();
}

class _BugReportPageState extends State<BugReportPage> {
  final _doing = TextEditingController();
  final _happened = TextEditingController();
  bool _busy = false;
  String? _error;
  BugReportDelivery? _done;

  @override
  void dispose() {
    _doing.dispose();
    _happened.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final delivery = await widget.onSubmit(_doing.text, _happened.text);
      if (mounted) setState(() => _done = delivery);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Não consegui gerar o arquivo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    return Scaffold(
      backgroundColor: kLibraryBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Reportar um bug', style: serifDisplay(fontSize: 24)),
                const SizedBox(height: 4),
                const Text(
                  'A tela, o som e o metrônomo estão parados. Conte o que '
                  'aconteceu; o arquivo leva também uma imagem da tela e o '
                  'registro dos últimos exercícios.',
                  style: TextStyle(color: kInkCaption),
                ),
                const SizedBox(height: 12),
                if (done == null) ...[
                  if (widget.screenshot != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: kBorder),
                          ),
                          child: Image.memory(
                            widget.screenshot!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _doing,
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
                    controller: _happened,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'O que aconteceu (o erro)?',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: kBadColor),
                    ),
                  ),
                if (done == null)
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : widget.onCancel,
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : () => unawaited(_generate()),
                        child: Text(_busy ? 'Gerando…' : 'Gerar relatório'),
                      ),
                    ],
                  )
                else
                  _Done(delivery: done, onClose: widget.onCancel),
              ],
            ),
          ),
        ),
      ),
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
