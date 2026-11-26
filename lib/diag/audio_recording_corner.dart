import 'package:flutter/material.dart';
import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_clock/zywny_clock.dart';

import 'audio_recording_cubit.dart';
import 'audio_recording_service.dart';

// O segurar do canto (kAudioRecordingHold) é do Cubit; o tamanho do canto é
// daqui. Reexportado, para quem já importava a constante desta tela.
export 'audio_recording_cubit.dart' show kAudioRecordingHold;

/// Lado do canto sensível, em dp.
const double kAudioRecordingCorner = 72;

/// Gravação de áudio do microfone, a qualquer hora e em qualquer tela
/// (modo depuração): segurar o canto inferior esquerdo por [kAudioRecordingHold]
/// liga; segurar de novo desliga e guarda o `.m4a`.
///
/// Ligar abre uma sessão de depuração no log ([DiagLog.beginSession], tipo
/// `gravacao`): tudo o que o app registrar enquanto grava vai para ela.
/// Desligar fecha a sessão e chama [onStopped], que abre a tela de envio do
/// relatório de bug.
///
/// Fica por cima da tela sem tomar os toques: o que está embaixo do canto
/// continua recebendo-os. Enquanto grava, um ponto vermelho com o tempo fica
/// à vista, também sem tomar toque.
class AudioRecordingCorner extends StatelessWidget {
  const AudioRecordingCorner({
    super.key,
    this.service,
    this.onStopped,
    required this.clock,
  });

  /// Os testes passam um falso; sem ele, cria o da plataforma ao primeiro uso.
  final AudioRecordingService? service;

  /// O relógio do app (CT05c): o segurar e o tempo da gravação.
  final AppClock clock;

  /// Chamado ao parar a gravação, depois de fechar a sessão de depuração.
  final VoidCallback? onStopped;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => AudioRecordingCubit(service: service, clock: clock),
    child: BlocListener<AudioRecordingCubit, AudioRecordingState>(
      // Parar a gravação abre a tela de envio: efeito de tela, no listener.
      listenWhen: (antes, depois) => depois.paradas != antes.paradas,
      listener: (_, _) => onStopped?.call(),
      child: BlocBuilder<AudioRecordingCubit, AudioRecordingState>(
        builder: (context, state) => Stack(
          children: [
            Positioned(
              left: 0,
              bottom: 0,
              width: kAudioRecordingCorner,
              height: kAudioRecordingCorner,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) => context
                    .read<AudioRecordingCubit>()
                    .pontoBaixo(e.pointer, e.position),
                onPointerMove: (e) => context
                    .read<AudioRecordingCubit>()
                    .pontoMovido(e.pointer, e.position),
                onPointerUp: (e) =>
                    context.read<AudioRecordingCubit>().pontoSolto(e.pointer),
                onPointerCancel: (e) =>
                    context.read<AudioRecordingCubit>().pontoSolto(e.pointer),
              ),
            ),
            if (state.gravando || state.aviso != null) _noticeChip(state),
          ],
        ),
      ),
    ),
  );

  /// O aviso de gravação (com o tempo) ou a última nota, no canto de baixo.
  Widget _noticeChip(AudioRecordingState state) => Positioned(
    left: 8,
    bottom: 8,
    child: IgnorePointer(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.gravando) ...[
                  const Icon(
                    Icons.fiber_manual_record,
                    color: Color(0xFFFF3B30),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  state.gravando
                      ? 'Gravando ${_formatar(state.decorrido)}'
                      : state.aviso!,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 12,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// "mm:ss", como o aviso da gravação mostra.
  static String _formatar(Duration decorrido) {
    final s = decorrido.inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }
}
