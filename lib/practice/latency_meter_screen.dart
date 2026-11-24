// A tela do medidor de latência do som do teclado (configurações → Teclado
// MIDI): o app manda notas ao teclado, escuta pelo microfone do celular e diz
// quanto o som demora a sair. A conta está em `LatencyMeterRunner`.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart' show MidiDevice;

import 'package:zywny_audio/engine_opener.dart';
import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_midi/midi_device_manager.dart';
import 'package:zywny_midi/midi_out_sound_engine.dart';

import '../diag/diag_screens.dart';
import '../ui/theme.dart';
import 'latency_meter.dart';
import 'latency_meter_runner.dart';
import 'mic_capture.dart';

/// Abre o medidor para o teclado [device].
Future<void> showLatencyMeter(
  BuildContext context, {
  required MidiDeviceManager devices,
  required MidiDevice device,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => LatencyMeterScreen(devices: devices, device: device),
  ),
);

class LatencyMeterScreen extends StatelessWidget {
  const LatencyMeterScreen({
    super.key,
    required this.devices,
    required this.device,
    this.createRunner,
  });

  final MidiDeviceManager devices;
  final MidiDevice device;

  /// A rodada; os testes trocam por uma de mundo simulado. O padrão usa o
  /// microfone, o MIDI e o motor de som de verdade.
  final LatencyMeterRunner Function(MidiDevice device)? createRunner;

  @override
  Widget build(BuildContext context) => BlocProvider(
    // Outro teclado, outra medida: refaz o Cubit (que fecha a rodada antiga).
    key: ValueKey(device.id),
    create: (_) => LatencyMeterScreenCubit(
      createRunner: () =>
          createRunner?.call(device) ??
          LatencyMeterRunner(
            mic: RecordMicCapture(),
            sender: FlutterMidiSender(),
            deviceId: device.id,
            openReference: openAppSoundEngine,
          ),
      saveLatency: (ms, corrected) =>
          devices.setSoundLatency(device.id, ms, corrected: corrected),
    ),
    child: _LatencyMeterView(device: device),
  );
}

/// A rodada em curso (se há) e o resultado da última.
class LatencyMeterScreenState extends Equatable {
  const LatencyMeterScreenState({this.runner, this.result});

  final LatencyMeterRunner? runner;
  final LatencyMeterResult? result;

  @override
  List<Object?> get props => [runner, result];
}

/// A tela do medidor: "Medir" faz uma rodada, grava a medida no teclado e
/// mostra o resultado; "Parar" a interrompe. Quem fecha a tela, para a rodada.
class LatencyMeterScreenCubit extends Cubit<LatencyMeterScreenState> {
  LatencyMeterScreenCubit({
    required this.createRunner,
    required this.saveLatency,
  }) : super(const LatencyMeterScreenState());

  /// Faz a rodada (os testes trocam por uma de mundo simulado).
  final LatencyMeterRunner Function() createRunner;

  /// Grava a medida no teclado.
  final Future<void> Function(double ms, bool corrected) saveLatency;

  /// Uma rodada: o microfone e os cliques, a medida (gravada no teclado) e o
  /// resultado.
  Future<void> medir() async {
    final runner = createRunner();
    emit(LatencyMeterScreenState(runner: runner));
    final result = await runner.run();
    final ms = result.keyboardMs;
    if (ms != null) await saveLatency(ms, result.corrected);
    if (!isClosed) emit(LatencyMeterScreenState(result: result));
    runner.dispose();
  }

  /// "Parar": a rodada acaba no próximo passo, com o que tiver.
  void parar() => state.runner?.cancel();

  @override
  Future<void> close() {
    state.runner?.cancel();
    return super.close();
  }
}

/// A página do medidor: o nome do teclado, as dicas, a rodada e o resultado.
class _LatencyMeterView extends StatelessWidget {
  const _LatencyMeterView({required this.device});

  final MidiDevice device;

  @override
  Widget build(BuildContext context) {
    return DiagScreen(
      name: 'medidor de latência',
      child: Scaffold(
        appBar: AppBar(title: const Text('Latência do som')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child:
                  BlocBuilder<LatencyMeterScreenCubit, LatencyMeterScreenState>(
                    builder: (context, state) => ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          device.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'O app manda algumas notas ao teclado e escuta, pelo '
                          'microfone do celular, quando o som sai. Assim mede o '
                          'atraso entre o app mandar a nota e você ouvi-la.',
                        ),
                        const SizedBox(height: 12),
                        ..._tips(),
                        const SizedBox(height: 16),
                        if (state.runner != null)
                          BlocProvider.value(
                            value: state.runner!.meter,
                            child: const _Running(),
                          ),
                        if (state.result != null)
                          _Report(result: state.result!),
                        const SizedBox(height: 16),
                        _measureButton(context, state),
                      ],
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  /// As três dicas de posição, volume e som do celular.
  List<Widget> _tips() => const [
    _Tip(
      Icons.near_me_outlined,
      'Deixe o celular perto do alto-falante do teclado, a uns 30 cm.',
    ),
    _Tip(
      Icons.volume_up_outlined,
      'Volume do teclado médio ou alto, e a sala quieta. Sem fone no teclado.',
    ),
    _Tip(
      Icons.phone_android,
      'O celular também toca uns cliques: use o alto-falante dele, sem fone '
      'Bluetooth.',
    ),
  ];

  /// "Medir" (ou "Medir de novo") quando não há medida em curso; "Parar" quando há.
  Widget _measureButton(BuildContext context, LatencyMeterScreenState state) {
    if (state.runner == null) {
      return FilledButton.icon(
        onPressed: () =>
            unawaited(context.read<LatencyMeterScreenCubit>().medir()),
        icon: const Icon(Icons.mic),
        label: Text(state.result == null ? 'Medir' : 'Medir de novo'),
      );
    }
    return OutlinedButton(
      onPressed: context.read<LatencyMeterScreenCubit>().parar,
      child: const Text('Parar'),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: kInkCaption),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: kInkCaption),
          ),
        ),
      ],
    ),
  );
}

/// O andamento da rodada e o volume do microfone. Lê o [LatencyMeterCubit] da
/// rodada, que está acima dele.
class _Running extends StatelessWidget {
  const _Running();

  static String _label(MeterProgress p) => switch (p.phase) {
    MeterPhase.idle || MeterPhase.starting => 'Abrindo o microfone…',
    MeterPhase.reference => 'Tocando o celular… ${p.done + 1} de ${p.total}',
    MeterPhase.keyboard => 'Tocando o teclado… ${p.done + 1} de ${p.total}',
    MeterPhase.analyzing ||
    MeterPhase.done ||
    MeterPhase.failed => 'Calculando…',
  };

  /// −70 a −20 dBFS na barra.
  static double _bar(double level) {
    final db = 20 * math.log(math.max(level, 1e-5)) / math.ln10;
    return ((db + 70) / 50).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      BlocSelector<LatencyMeterCubit, LatencyMeterState, MeterProgress>(
        selector: (state) => state.progress,
        builder: (context, p) => Text(
          _label(p),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Volume que o microfone ouve',
        style: TextStyle(fontSize: 12, color: kInkCaption),
      ),
      const SizedBox(height: 4),
      BlocSelector<LatencyMeterCubit, LatencyMeterState, double>(
        selector: (state) => state.level,
        builder: (context, level) =>
            LinearProgressIndicator(value: _bar(level), minHeight: 8),
      ),
    ],
  );
}

/// O resultado: o número, o que ele quer dizer e o que está por trás dele.
class _Report extends StatelessWidget {
  const _Report({required this.result});

  final LatencyMeterResult result;

  @override
  Widget build(BuildContext context) {
    final failure = result.failure;
    if (failure != null) return _Failure(result: result);
    final ms = result.keyboardMs!;
    final stats = result.keyboard!;
    final mic = result.micDelayMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${ms.round()} ms', style: serifDisplay(fontSize: 40)),
        Text(
          'de atraso entre o app mandar a nota e o teclado soar',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          latencyVerdict(ms),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          stats.stdMs < 4
              ? 'Estável: o atraso quase não varia de uma nota para outra '
                    '(${stats.used} de ${stats.total} notas ouvidas).'
              : 'Varia uns ±${stats.stdMs.round()} ms de uma nota para outra '
                    '(${stats.used} de ${stats.total} notas ouvidas). Essa '
                    'oscilação atrapalha o ritmo mais que o atraso fixo.',
        ),
        const SizedBox(height: 8),
        Text(
          mic != null
              ? 'O microfone mediu ${stats.medianMs.round()} ms; descontei '
                    '${mic.round()} ms do próprio microfone do celular.'
              : _uncorrected(result.referenceStatus, stats.medianMs),
          style: const TextStyle(fontSize: 12, color: kInkCaption),
        ),
        if (result.pingsMs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Notas: ${[for (final p in result.pingsMs) p == null ? '—' : p.round()].join(' · ')} ms (medida crua do microfone)',
            style: const TextStyle(fontSize: 12, color: kInkCaption),
          ),
        ],
      ],
    );
  }

  static String _uncorrected(MeterReference status, double raw) =>
      switch (status) {
        MeterReference.unreliable =>
          'Não consegui medir o atraso do microfone (o som do celular não '
              'saiu pelo alto-falante dele? fone Bluetooth?). O valor inclui '
              'o atraso do microfone, em geral de 10 a 40 ms: o do teclado '
              'é menor que ${raw.round()} ms.',
        _ =>
          'O valor inclui o atraso do microfone do celular, em geral de 10 '
              'a 40 ms: o do teclado é menor que ${raw.round()} ms.',
      };
}

class _Failure extends StatelessWidget {
  const _Failure({required this.result});

  final LatencyMeterResult result;

  @override
  Widget build(BuildContext context) {
    final text = switch (result.failure!) {
      MeterFailure.micDenied =>
        'Sem a permissão do microfone não dá para medir. Libere o '
            'microfone para o app nas configurações do Android e tente de '
            'novo.',
      MeterFailure.micUnavailable =>
        'Não consegui abrir o microfone. Outro app está usando? Feche-o e '
            'tente de novo.',
      MeterFailure.heardNothing when result.heardSpeaker =>
        'O microfone ouviu o celular, mas quase não ouviu o teclado. '
            'Aproxime o celular do alto-falante, aumente o volume do '
            'teclado e confira se ele toca as notas que chegam por MIDI '
            '(sem fone ligado).',
      MeterFailure.heardNothing =>
        'O microfone não ouviu nada. Confira se o celular está perto do '
            'teclado, se o volume do teclado e o do celular estão '
            'ligados, e se o microfone está liberado para o app.',
      MeterFailure.cancelled => 'Medida interrompida.',
    };
    return Text(text, style: const TextStyle(color: kBadColor));
  }
}
