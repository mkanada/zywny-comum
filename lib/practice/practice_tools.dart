// T04: telas dos acessórios de treino — loop A-B e calibração de latência.
// Só UI; o estado e a ligação com agendador/player ficam em `main.dart`.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:zywny_audio/sound_engine.dart';

import 'package:zywny_midi/midi_input_service.dart';

import '../ui/side_panel.dart';
import '../ui/theme.dart';
import 'latency_calibration.dart';
import 'measure_text.dart';
import 'practice_report.dart';
import 'review_button.dart';

/// O que a escolha do trecho sabe antes de abrir: quantos compassos há, o que
/// está tocando e o trecho já escolhido (se há).
typedef LoopChoice = ({int total, int current, ({int a, int b})? initial});

/// Escolha do trecho: dois compassos (índices 0-based em ordem de execução —
/// com repetição, cada volta é uma ocorrência própria). Devolve `(a, b)` ou
/// `null` se cancelou; [onClear] pede para desligar o loop.
Future<({int a, int b})?> showLoopSheet(
  BuildContext context,
  LoopChoice choice, {
  required VoidCallback onClear,
  bool sidePanel = false,
}) {
  return showSheetOrSidePanel<({int a, int b})>(
    context,
    sidePanel: sidePanel,
    title: 'Repetir um trecho',
    builder: (context) =>
        _LoopSheet(choice: choice, onClear: onClear, sidePanel: sidePanel),
  );
}

/// A folha de [showLoopSheet]: o início e o fim do trecho, e os botões.
class _LoopSheet extends StatefulWidget {
  const _LoopSheet({
    required this.choice,
    required this.onClear,
    required this.sidePanel,
  });

  final LoopChoice choice;
  final VoidCallback onClear;
  final bool sidePanel;

  @override
  State<_LoopSheet> createState() => _LoopSheetState();
}

class _LoopSheetState extends State<_LoopSheet> {
  late int _a = widget.choice.initial?.a ?? widget.choice.current;
  late int _b =
      widget.choice.initial?.b ??
      (widget.choice.current + 1 < widget.choice.total
          ? widget.choice.current + 1
          : widget.choice.current);

  int get _last => widget.choice.total - 1;

  void _setA(int v) => setState(() {
    _a = v.clamp(0, _last);
    if (_b < _a) _b = _a;
  });

  void _setB(int v) => setState(() {
    _b = v.clamp(0, _last);
    if (_a > _b) _a = _b;
  });

  @override
  Widget build(BuildContext context) {
    final choice = widget.choice;
    return sheetBody(
      sidePanel: widget.sidePanel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _a == _b
                ? 'Repetir o compasso ${_a + 1}'
                : 'Repetir do compasso ${_a + 1} ao ${_b + 1}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (choice.total > 1) ...[
            _LoopSlider(
              label: 'Início',
              value: _a,
              total: choice.total,
              onChanged: _setA,
              onCurrent: () => _setA(choice.current),
            ),
            _LoopSlider(
              label: 'Fim',
              value: _b,
              total: choice.total,
              onChanged: _setB,
              onCurrent: () => _setB(choice.current),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context, (a: _a, b: _b)),
            child: const Text('Repetir este trecho'),
          ),
          if (choice.initial != null)
            TextButton(
              onPressed: () {
                widget.onClear();
                Navigator.pop(context);
              },
              child: const Text('Desligar o loop'),
            ),
        ],
      ),
    );
  }
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
      scrollable: true,
      title: const Text('Ajustar o atraso'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (_phase) {
            _Phase.idle =>
              'Vão soar $kCalibrationClicks cliques. Aperte qualquer tecla '
                  'do teclado junto com cada um.',
            _Phase.running =>
              'Toque junto com os cliques… '
                  '${_run?.clicksPlayed ?? 0}/$kCalibrationClicks',
            _Phase.done =>
              result == null
                  ? 'Não deu para medir — toque junto de pelo menos 5 cliques.'
                  : 'Atraso: ${result.toStringAsFixed(0)} ms'
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

/// As opções do resumo do treino (ver [showPracticeSummary]).
class PracticeSummaryOptions {
  const PracticeSummaryOptions({
    this.onRepeatWorst,
    this.wrongCount = 0,
    this.reviewHasSides = false,
    this.onReview,
    this.legend,
    this.sidePanel = false,
  });

  /// Repetir os compassos com mais erros; sem ele, o botão não aparece.
  final void Function(List<MeasureStats> worst)? onRepeatWorst;

  /// Notas erradas do treino e o que fazer para vê-las na partitura; `null`
  /// esconde o botão.
  final int wrongCount;
  final bool reviewHasSides;
  final VoidCallback? onReview;

  /// A legenda da partitura, se há uma.
  final Widget? legend;

  /// No celular o resumo entra pela lateral (ver [showSheetOrSidePanel]).
  final bool sidePanel;
}

/// O resumo de um treino: a precisão, as contagens, o tempo e, com "Detalhes",
/// a média de atraso e os compassos que deram mais trabalho.
Future<void> showPracticeSummary(
  BuildContext context,
  PracticeReport report, {
  PracticeSummaryOptions options = const PracticeSummaryOptions(),
}) {
  return showSheetOrSidePanel<void>(
    context,
    sidePanel: options.sidePanel,
    title: 'Resumo do treino',
    builder: (context) =>
        _PracticeSummarySheet(report: report, options: options),
  );
}

/// A folha de [showPracticeSummary]: o botão de detalhes é o único estado.
class _PracticeSummarySheet extends StatefulWidget {
  const _PracticeSummarySheet({required this.report, required this.options});

  final PracticeReport report;
  final PracticeSummaryOptions options;

  @override
  State<_PracticeSummarySheet> createState() => _PracticeSummarySheetState();
}

class _PracticeSummarySheetState extends State<_PracticeSummarySheet> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final options = widget.options;
    final worst = report.worstMeasures();
    return sheetBody(
      sidePanel: options.sidePanel,
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
          if (!report.isEmpty) ..._counts(report, worst),
          if (options.legend != null) ...[
            const SizedBox(height: 12),
            options.legend!,
          ],
          const SizedBox(height: 12),
          if (worst.isNotEmpty && options.onRepeatWorst != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                options.onRepeatWorst!(worst);
              },
              child: const Text('Repetir os compassos com mais erros'),
            ),
          if (options.onReview != null && options.wrongCount > 0)
            ...reviewButton(
              hasSides: options.reviewHasSides,
              onPressed: () {
                Navigator.pop(context);
                options.onReview!();
              },
            ),
          if (!report.isEmpty)
            TextButton(
              onPressed: () => setState(() => _details = !_details),
              child: Text(_details ? 'Esconder detalhes' : 'Detalhes'),
            ),
          if (_details && !report.isEmpty) ..._detailRows(report, worst),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  /// As contagens (certas, fora do tempo, erradas, perdidas), o tempo e os
  /// compassos que deram mais trabalho.
  List<Widget> _counts(PracticeReport report, List<MeasureStats> worst) => [
    const SizedBox(height: 8),
    Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _Stat('${report.correct}', 'certas', kGoodColor),
        _Stat('${report.early + report.late}', 'fora do tempo', kOkColor),
        _Stat('${report.wrong}', 'erradas', kBadColor),
        _Stat('${report.missed}', 'perdidas', kLowScoreColor),
      ],
    ),
    const SizedBox(height: 8),
    Text(practiceTimingPhrase(report)),
    if (worst.isNotEmpty) ...[
      const SizedBox(height: 4),
      Text(
        'Deram mais trabalho: compassos '
        '${joinMeasureNumbers([for (final m in worst) m.index + 1], ranges: false)}.',
      ),
    ],
  ];

  /// Os detalhes: a média e o desvio do atraso, e os compassos com erro.
  List<Widget> _detailRows(PracticeReport report, List<MeasureStats> worst) => [
    Text(
      'Em média ${_signedMs(report.meanDeltaMs)} '
      '(desvio ${report.meanAbsDeltaMs.round()} ms'
      '${report.stdDevMs > 0 ? ', regularidade ±${report.stdDevMs.round()} ms' : ''})',
      style: const TextStyle(color: kInkCaption),
    ),
    for (final m in worst)
      Text(
        'Compasso ${m.index + 1}'
        '${m.pass > 1 ? ' (${m.pass}ª vez)' : ''}: '
        '${m.wrong} erradas, ${m.missed} perdidas, '
        '${m.imprecise} fora do tempo',
      ),
    const SizedBox(height: 8),
  ];
}

/// O atraso (ou adiantamento) em ms, em português.
String _signedMs(double ms) {
  if (ms.abs() < 1) return 'no tempo';
  return '${ms.abs().round()} ms ${ms < 0 ? 'adiantado' : 'atrasado'}';
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
