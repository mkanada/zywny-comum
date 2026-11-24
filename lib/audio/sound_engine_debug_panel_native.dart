import 'package:flutter/material.dart';
import 'package:zywny_audio/native_sound_engine.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import 'sound_engine_debug_cubit.dart';

/// Painel de depuração do motor de áudio (K02/K03), só com `--debug`: um
/// botão que carrega um `.sf2` (D-SF ainda aberta — sem asset embutido
/// ainda) e toca uma escala de teste, e o sample rate/latência/estatísticas
/// do motor nativo. Fora de escopo em K03: tocar a partitura de verdade
/// (isso é K04).
///
/// O motor e o estado ficam no [SoundEngineDebugCubit], criado aqui; o painel
/// em si não guarda estado.
class SoundEngineDebugPanel extends StatelessWidget {
  const SoundEngineDebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SoundEngineDebugCubit(),
      child: const _SoundEngineDebugView(),
    );
  }
}

class _SoundEngineDebugView extends StatelessWidget {
  const _SoundEngineDebugView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SoundEngineDebugCubit>();
    return BlocBuilder<SoundEngineDebugCubit, SoundEngineDebugState>(
      builder: (context, state) {
        // Relido a cada tique (`serial`): o motor muda os contadores sem avisar.
        final NativeSoundEngine? engine = cubit.motor;
        final stats = engine == null
            ? null
            : 'sample rate: ${engine.sampleRate} Hz  •  '
                  'latência: ${(engine.outputLatencySeconds * 1000).round()} ms  •  '
                  'underruns: ${engine.stat(zyStatUnderruns)}  •  '
                  'descartados: ${engine.stat(zyStatDroppedEvents)}';
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: state.busy ? null : cubit.tocarEscalaDeTeste,
                  icon: const Icon(Icons.graphic_eq),
                  label: const Text('Tocar escala de teste (.sf2)'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.status,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (stats != null)
                        Text(
                          stats,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
