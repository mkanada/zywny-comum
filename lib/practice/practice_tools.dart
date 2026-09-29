// T04: telas dos acessórios de treino — loop A-B e calibração de latência.
// Só UI; o estado e a ligação com agendador/player ficam em `main.dart`.
import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/latency_calibration.dart';
import '../audio/sound_engine.dart';
import '../midi/midi_input_service.dart';
import '../ui/theme.dart';
import 'practice_report.dart';

/// Escolha do trecho: dois compassos (índices 0-based em ordem de execução —
/// com repetição, cada volta é uma ocorrência própria). Devolve `(a, b)` ou
/// `null` se cancelou; [clear] pede para desligar o loop.
Future<({int a, int b})?> showLoopSheet(
  BuildContext context, {
  required int total,
  required int current,
  ({int a, int b})? initial,
  required VoidCallback onClear,
}) {
  return showModalBottomSheet<({int a, int b})>(
    context: context,
    backgroundColor: kSurface,
    isScrollControlled: true,
    builder: (context) {
      var a = initial?.a ?? current;
      var b = initial?.b ?? (current + 1 < total ? current + 1 : current);
      return StatefulBuilder(
        builder: (context, setSheetState) {
          void setA(int v) => setSheetState(() {
            a = v.clamp(0, total - 1);
            if (b < a) b = a;
          });
          void setB(int v) => setSheetState(() {
            b = v.clamp(0, total - 1);
            if (a > b) a = b;
          });
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    a == b
                        ? 'Repetir o compasso ${a + 1}'
                        : 'Repetir do compasso ${a + 1} ao ${b + 1}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (total > 1) ...[
                    _LoopSlider(
                      label: 'Início',
                      value: a,
                      total: total,
                      onChanged: setA,
                      onCurrent: () => setA(current),
                    ),
                    _LoopSlider(
                      label: 'Fim',
                      value: b,
                      total: total,
                      onChanged: setB,
                      onCurrent: () => setB(current),
                    ),
                  ],
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, (a: a, b: b)),
                    child: const Text('Repetir este trecho'),
                  ),
                  if (initial != null)
                    TextButton(
                      onPressed: () {
                        onClear();
                        Navigator.pop(context);
                      },
                      child: const Text('Desligar o loop'),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _LoopSlider extends StatelessWidget {
  const _LoopSlider({
    required this.label,
    required this.value,
    required this.total,
    required this.onChanged,
    required this.onCurrent,
  });

  final String label;
  final int value;
  final int total;
  final ValueChanged<int> onChanged;
  final VoidCallback onCurrent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 44, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: (total - 1).toDouble(),
            divisions: total > 1 ? total - 1 : null,
            activeColor: kAccent,
            label: '${value + 1}',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        TextButton(onPressed: onCurrent, child: const Text('Atual')),
      ],
    );
  }
}

/// Calibração de latência (T04): 8 cliques a 100 bpm, o aluno aperta
/// qualquer tecla junto de cada um. Devolve a latência escolhida (ms) —
/// `null` se cancelou.
Future<double?> showCalibrationDialog(
  BuildContext context, {
  required SoundEngine engine,
  required MidiInputService input,
  required String deviceName,
}) {
  return showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _CalibrationDialog(
      engine: engine,
      input: input,
      deviceName: deviceName,
    ),
  );
}

class _CalibrationDialog extends StatefulWidget {
  const _CalibrationDialog({
    required this.engine,
    required this.input,
    required this.deviceName,
  });

  final SoundEngine engine;
  final MidiInputService input;
  final String deviceName;

  @override
  State<_CalibrationDialog> createState() => _CalibrationDialogState();
}

enum _Phase { idle, running, done }

class _CalibrationDialogState extends State<_CalibrationDialog> {
  _Phase _phase = _Phase.idle;
  LatencyCalibration? _run;
  double? _result;
  Timer? _ticker;

  void _start() {
    final run = LatencyCalibration(engine: widget.engine, input: widget.input);
    _run = run;
    setState(() => _phase = _Phase.running);
    run.start();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => mounted ? setState(() {}) : null,
    );
    unawaited(
      run.result.then((ms) {
        _ticker?.cancel();
        if (mounted) {
          setState(() {
            _result = ms;
            _phase = _Phase.done;
          });
        }
      }),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _run?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AlertDialog(
      title: const Text('Calibrar latência'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (_phase) {
            _Phase.idle =>
              'Vão soar $kCalibrationClicks cliques. Aperte qualquer tecla '
                  'de ${widget.deviceName} junto com cada um, no pulso.',
            _Phase.running =>
              'Toque junto com os cliques… '
                  '${_run?.clicksPlayed ?? 0}/$kCalibrationClicks',
            _Phase.done =>
              result == null
                  ? 'Não deu para medir — toque junto de pelo menos 5 cliques.'
                  : 'Latência: ${result.toStringAsFixed(0)} ms'
                        '${result > kCalibrationWarnMs ? '\nAlta (> ${kCalibrationWarnMs.round()} ms) — fone Bluetooth?' : ''}',
          }),
          if (_phase == _Phase.running) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (_run?.clicksPlayed ?? 0) / kCalibrationClicks,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_phase == _Phase.done ? 'Descartar' : 'Cancelar'),
        ),
        if (_phase != _Phase.running)
          TextButton(
            onPressed: _start,
            child: Text(_phase == _Phase.idle ? 'Começar' : 'Repetir'),
          ),
        if (_phase == _Phase.done && result != null)
          FilledButton(
            onPressed: () => Navigator.pop(context, result),
            child: const Text('Usar'),
          ),
      ],
    );
  }
}

/// Resumo do treino em tempo real (T03). [onRepeatWorst] recebe os compassos
/// (ocorrências) com mais erros; `null` desabilita o botão.
Future<void> showPracticeSummary(
  BuildContext context,
  PracticeReport report, {
  void Function(List<MeasureStats> worst)? onRepeatWorst,
}) {
  final worst = report.worstMeasures();
  String signed(double ms) {
    if (ms.abs() < 1) return 'no tempo';
    return '${ms.abs().round()} ms ${ms < 0 ? 'adiantado' : 'atrasado'}';
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurface,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              report.isEmpty
                  ? 'Nenhuma nota avaliada'
                  : 'Precisão ${(report.accuracy * 100).round()}%',
              style: serifDisplay(fontSize: 22),
            ),
            if (!report.isEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _Stat('${report.correct}', 'certas', kGoodColor),
                  _Stat(
                    '${report.early + report.late}',
                    'fora do tempo',
                    kOkColor,
                  ),
                  if (report.wrong > 0 || report.extra == 0)
                    _Stat('${report.wrong}', 'erradas', kBadColor),
                  if (report.extra > 0)
                    _Stat('${report.extra}', 'toques extras', kBadColor),
                  _Stat('${report.missed}', 'perdidas', kLowScoreColor),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Em média ${signed(report.meanDeltaMs)} '
                '(desvio ${report.meanAbsDeltaMs.round()} ms'
                '${report.stdDevMs > 0 ? ', regularidade ±${report.stdDevMs.round()} ms' : ''})',
                style: const TextStyle(color: kInkCaption),
              ),
              if (worst.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Compassos com mais erros',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final m in worst)
                  Text(
                    'Compasso ${m.index + 1}'
                    '${m.pass > 1 ? ' (${m.pass}ª vez)' : ''}: '
                    '${m.wrong} erradas, ${m.missed} perdidas, '
                    '${m.imprecise} fora do tempo',
                  ),
              ],
            ],
            const SizedBox(height: 12),
            if (worst.isNotEmpty && onRepeatWorst != null)
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  onRepeatWorst(worst);
                },
                child: const Text('Repetir os compassos com mais erros'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        TextSpan(text: ' $label'),
      ],
    ),
  );
}
