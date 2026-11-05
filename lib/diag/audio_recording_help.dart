import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'audio_recording_service.dart';

/// Nas configurações: como gravar o microfone (segurar o canto inferior
/// esquerdo, ver `AudioRecordingCorner`), uma figura de onde fica a área e o
/// atalho para a pasta das gravações.
///
/// [open] troca a abertura da pasta nos testes.
class AudioRecordingHelp extends StatelessWidget {
  const AudioRecordingHelp({super.key, this.open = openAudioRecordingsFolder});

  final Future<bool> Function() open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folder = audioRecordingsFolderLabel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Em qualquer tela, segure o dedo por 1 segundo no canto inferior '
            'esquerdo para começar a gravar o som do microfone. Segure de '
            'novo para parar: o arquivo (.m4a, AAC a 160 kbps) fica em '
            '$folder. Enquanto grava, o app registra tudo o que faz, como '
            'numa sessão de depuração; ao parar, abre a tela para enviar o '
            'relatório de bug.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Center(child: AudioCornerFigure()),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.folder_open_outlined, size: 20),
          title: const Text('Abrir a pasta das gravações'),
          subtitle: Text(folder),
          trailing: const Text(
            'Abrir',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: kAccent,
            ),
          ),
          onTap: () => unawaited(_openFolder(context)),
        ),
      ],
    );
  }

  Future<void> _openFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final folder = audioRecordingsFolderLabel();
    final ok = await open();
    if (!ok) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Não consegui abrir a pasta. Procure por $folder no '
            'gerenciador de arquivos.',
          ),
        ),
      );
    }
  }
}

/// A tela do aparelho (deitado, como na partitura) com o canto inferior
/// esquerdo realçado e a mão que o segura.
class AudioCornerFigure extends StatelessWidget {
  const AudioCornerFigure({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Figura: a área de gravação é o canto inferior esquerdo da tela, '
          'um quadrado pequeno; segure 1 segundo.',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: CustomPaint(painter: _CornerPainter(Theme.of(context))),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter(this.theme);

  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = theme.colorScheme.outline;
    final soft = theme.colorScheme.outlineVariant;
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas.drawRRect(
      body,
      Paint()..color = theme.colorScheme.surfaceContainerHighest,
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // A "partitura": cinco pautas, só para dar contexto.
    final staff = Paint()
      ..color = soft
      ..strokeWidth = 1;
    for (var s = 0; s < 2; s++) {
      final top = size.height * (0.18 + s * 0.28);
      for (var i = 0; i < 5; i++) {
        final y = top + i * size.height * 0.03;
        canvas.drawLine(
          Offset(size.width * 0.08, y),
          Offset(size.width * 0.92, y),
          staff,
        );
      }
    }

    // O canto sensível: 72 dp numa tela de ~700 dp, um pouco exagerado.
    final side = size.width * 0.17;
    final corner = Rect.fromLTWH(0, size.height - side, side, side);
    final clip = RRect.fromRectAndCorners(
      corner,
      bottomLeft: const Radius.circular(14),
    );
    canvas.drawRRect(clip, Paint()..color = kAccent.withValues(alpha: 0.28));
    canvas.drawRRect(
      clip,
      Paint()
        ..color = kAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // O dedo, no meio do canto.
    final icon = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.touch_app.codePoint),
        style: TextStyle(
          fontFamily: Icons.touch_app.fontFamily,
          package: Icons.touch_app.fontPackage,
          fontSize: side * 0.62,
          color: kAccentDark,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    icon.paint(canvas, corner.center - Offset(icon.width / 2, icon.height / 2));

    final label = TextPainter(
      text: TextSpan(
        text: 'segure 1 s',
        style: TextStyle(
          fontSize: size.width * 0.055,
          fontWeight: FontWeight.w600,
          color: kAccentDark,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(side + size.width * 0.03, size.height - label.height - 8),
    );
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.theme != theme;
}
