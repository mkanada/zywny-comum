// T04: telas dos acessórios de treino — loop A-B e calibração de latência.
// Só UI; o estado e a ligação com agendador/player ficam em `main.dart`.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:zywny_audio/sound_engine.dart';

import 'package:zywny_bloc/zywny_bloc.dart';
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

/// Os dois compassos da escolha, 0-based: o início (`a`) e o fim (`b`).
class LoopSheetState extends Equatable {
  const LoopSheetState({required this.a, required this.b});

  final int a;
  final int b;

  LoopSheetState copyWith({int? a, int? b}) =>
      LoopSheetState(a: a ?? this.a, b: b ?? this.b);

  @override
  List<Object?> get props => [a, b];
}

/// A folha do loop: o início e o fim, presos entre 0 e o último compasso. O
/// fim nunca fica antes do início, nem o início depois do fim.
class LoopSheetCubit extends Cubit<LoopSheetState> {
  LoopSheetCubit(this.choice)
    : super(
        LoopSheetState(
          a: choice.initial?.a ?? choice.current,
          b:
              choice.initial?.b ??
              (choice.current + 1 < choice.total
                  ? choice.current + 1
                  : choice.current),
        ),
      );

  /// O que a folha sabe antes de abrir (ver [LoopChoice]).
  final LoopChoice choice;

  int get _ultimo => choice.total - 1;

  /// Põe o início no compasso [v] (preso ao intervalo).
  void inicio(int v) {
    final a = v.clamp(0, _ultimo);
    if (isClosed) return;
    emit(state.copyWith(a: a, b: state.b < a ? a : state.b));
  }

  /// Põe o fim no compasso [v] (preso ao intervalo).
  void fim(int v) {
    final b = v.clamp(0, _ultimo);
    if (isClosed) return;
    emit(state.copyWith(a: state.a > b ? b : state.a, b: b));
  }
}

/// A folha de [showLoopSheet]: o início e o fim do trecho, e os botões.
class _LoopSheet extends StatelessWidget {
  const _LoopSheet({
    required this.choice,
    required this.onClear,
    required this.sidePanel,
  });

  final LoopChoice choice;
  final VoidCallback onClear;
  final bool sidePanel;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => LoopSheetCubit(choice),
    child: BlocBuilder<LoopSheetCubit, LoopSheetState>(
      builder: (context, state) => _corpo(context, state),
    ),
  );

  Widget _corpo(BuildContext context, LoopSheetState state) {
    final cubit = context.read<LoopSheetCubit>();
    return sheetBody(
      sidePanel: sidePanel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.a == state.b
                ? 'Repetir o compasso ${state.a + 1}'
                : 'Repetir do compasso ${state.a + 1} ao ${state.b + 1}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (choice.total > 1) ...[
            _LoopSlider(
              label: 'Início',
              value: state.a,
              total: choice.total,
              onChanged: cubit.inicio,
              onCurrent: () => cubit.inicio(choice.current),
            ),
            _LoopSlider(
              label: 'Fim',
              value: state.b,
              total: choice.total,
              onChanged: cubit.fim,
              onCurrent: () => cubit.fim(choice.current),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context, (a: state.a, b: state.b)),
            child: const Text('Repetir este trecho'),
          ),
          if (choice.initial != null)
            TextButton(
              onPressed: () {
                onClear();
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

/// As fases da calibração: antes dos cliques, tocando, e com o resultado.
enum CalibrationPhase { idle, running, done }

/// O que a caixa de calibração mostra: a fase, quantos cliques já soaram e o
/// atraso medido (só na fase `done`; `null` se não deu para medir).
class CalibrationState extends Equatable {
  const CalibrationState({
    this.phase = CalibrationPhase.idle,
    this.clicksPlayed = 0,
    this.result,
  });

  final CalibrationPhase phase;
  final int clicksPlayed;
  final double? result;

  CalibrationState copyWith({
    CalibrationPhase? phase,
    int? clicksPlayed,
    double? result,
  }) => CalibrationState(
    phase: phase ?? this.phase,
    clicksPlayed: clicksPlayed ?? this.clicksPlayed,
    result: result ?? this.result,
  );

  @override
  List<Object?> get props => [phase, clicksPlayed, result];
}

/// A rodada da calibração: [comecar] agenda os cliques, uma tarefa periódica
/// conta os que já soaram para a barra, e o resultado sai quando a rodada
/// acaba. [close] para a rodada e a contagem.
class CalibrationCubit extends Cubit<CalibrationState> {
  CalibrationCubit({required this.engine, required this.input})
    : super(const CalibrationState());

  final SoundEngine engine;
  final MidiInputService input;

  LatencyCalibration? _rodada;
  Timer? _contador;
  static const _tique = Duration(milliseconds: 100);

  /// Começa (ou recomeça) a rodada.
  void comecar() {
    final rodada = LatencyCalibration(engine: engine, input: input);
    _rodada = rodada;
    emit(state.copyWith(phase: CalibrationPhase.running, clicksPlayed: 0));
    rodada.start();
    // A barra da calibração lê o motor de som no ritmo dele (decisão 2).
    _contador = Timer.periodic(_tique, (_) => _contar()); // relógio: decisão 2
    unawaited(
      rodada.result.then((ms) {
        _contador?.cancel();
        if (isClosed) return;
        emit(state.copyWith(phase: CalibrationPhase.done, result: ms));
      }),
    );
  }

  void _contar() {
    if (isClosed) return;
    emit(state.copyWith(clicksPlayed: _rodada?.clicksPlayed ?? 0));
  }

  @override
  Future<void> close() {
    _contador?.cancel();
    _rodada?.cancel();
    return super.close();
  }
}

/// Calibração de latência (ver [showCalibrationDialog]): a caixa com o botão
/// de começar, a barra dos cliques e o resultado.
class _CalibrationDialog extends StatelessWidget {
  const _CalibrationDialog({
    required this.engine,
    required this.input,
    required this.deviceName,
  });

  final SoundEngine engine;
  final MidiInputService input;
  final String deviceName;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => CalibrationCubit(engine: engine, input: input),
    child: BlocBuilder<CalibrationCubit, CalibrationState>(
      builder: (context, state) => _caixa(context, state),
    ),
  );

  Widget _caixa(BuildContext context, CalibrationState state) {
    final result = state.result;
    return AlertDialog(
      scrollable: true,
      title: const Text('Ajustar o atraso'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (state.phase) {
            CalibrationPhase.idle =>
              'Vão soar $kCalibrationClicks cliques. Aperte qualquer tecla '
                  'do teclado junto com cada um.',
            CalibrationPhase.running =>
              'Toque junto com os cliques… '
                  '${state.clicksPlayed}/$kCalibrationClicks',
            CalibrationPhase.done =>
              result == null
                  ? 'Não deu para medir — toque junto de pelo menos 5 cliques.'
                  : 'Atraso: ${result.toStringAsFixed(0)} ms'
                        '${result > kCalibrationWarnMs ? '\nAlta (> ${kCalibrationWarnMs.round()} ms) — fone Bluetooth?' : ''}',
          }),
          if (state.phase == CalibrationPhase.running) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: state.clicksPlayed / kCalibrationClicks,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            state.phase == CalibrationPhase.done ? 'Descartar' : 'Cancelar',
          ),
        ),
        if (state.phase != CalibrationPhase.running)
          TextButton(
            onPressed: context.read<CalibrationCubit>().comecar,
            child: Text(
              state.phase == CalibrationPhase.idle ? 'Começar' : 'Repetir',
            ),
          ),
        if (state.phase == CalibrationPhase.done && result != null)
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

/// Se o resumo mostra os detalhes (o único estado da folha).
class PracticeSummaryState extends Equatable {
  const PracticeSummaryState({this.details = false});

  final bool details;

  PracticeSummaryState copyWith({bool? details}) =>
      PracticeSummaryState(details: details ?? this.details);

  @override
  List<Object?> get props => [details];
}

/// Abre e fecha os detalhes do resumo do treino.
class PracticeSummaryCubit extends Cubit<PracticeSummaryState> {
  PracticeSummaryCubit() : super(const PracticeSummaryState());

  /// "Detalhes" ou "Esconder detalhes".
  void alternarDetalhes() => emit(state.copyWith(details: !state.details));
}

/// A folha de [showPracticeSummary]: o botão de detalhes é o único estado.
class _PracticeSummarySheet extends StatelessWidget {
  const _PracticeSummarySheet({required this.report, required this.options});

  final PracticeReport report;
  final PracticeSummaryOptions options;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PracticeSummaryCubit(),
    child: BlocBuilder<PracticeSummaryCubit, PracticeSummaryState>(
      builder: (context, state) => _corpo(context, state.details),
    ),
  );

  Widget _corpo(BuildContext context, bool details) {
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
              onPressed: context.read<PracticeSummaryCubit>().alternarDetalhes,
              child: Text(details ? 'Esconder detalhes' : 'Detalhes'),
            ),
          if (details && !report.isEmpty) ..._detailRows(report, worst),
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
