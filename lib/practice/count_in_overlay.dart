// Contagem regressiva por cima da partitura: no compasso a mais que antecede
// tudo o que anda no tempo (play, tempo real, ritmo), o número de tempos que
// faltam aparece grande e nítido no clique e esmaece até o clique seguinte —
// cresce, desfoca e fica transparente.
//
// O widget não sabe contar: a cada quadro pergunta a [CountInOverlay.read]
// onde a contagem está (o agendador de áudio, que é quem clica, ou a
// contagem muda da tela) e só redesenha quando a resposta muda.
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/metronome.dart';

/// Azul da contagem.
const kCountInColor = Color(0xFF1F4FD8);

/// Quanto o número cresce ao longo do tempo (`0.6` = termina 60% maior).
const kCountInGrowth = 0.6;

/// Desfoque no fim do tempo, em fração do tamanho da fonte.
const kCountInBlur = 36 / 420;

/// Opacidade máxima da contagem no celular.
const kCountInPhoneMaxOpacity = 0.5;

/// Opacidade do número em [progress] do tempo: segura um instante nítido e
/// depois cai até zero.
double countInOpacityAt(double progress) =>
    (1 - math.pow(progress, 1.4)).clamp(0.0, 1.0).toDouble();

class CountInOverlay extends StatefulWidget {
  const CountInOverlay({
    super.key,
    required this.active,
    required this.read,
    this.phone = false,
  });

  /// Celular (U09): o número fica na metade direita da caixa, sem crescer
  /// nem desfocar e com no máximo [kCountInPhoneMaxOpacity] — o compasso em
  /// que o aluno vai entrar (à esquerda) fica inteiro à vista. Fora do
  /// celular, a contagem grande e central de sempre.
  final bool phone;

  /// Há algo tocando: só então [read] é consultado (a cada quadro).
  final bool active;

  /// A contagem em curso, ou `null` fora dela.
  final CountInTick? Function() read;

  @override
  State<CountInOverlay> createState() => _CountInOverlayState();
}

class _CountInOverlayState extends State<CountInOverlay>
    with SingleTickerProviderStateMixin {
  final _tick = ValueNotifier<CountInTick?>(null);
  late final Ticker _ticker = createTicker((_) => _tick.value = widget.read());

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(CountInOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active == _ticker.isActive) return;
    if (widget.active) {
      _tick.value = widget.read();
      _ticker.start();
    } else {
      _ticker.stop();
      _tick.value = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<CountInTick?>(
        valueListenable: _tick,
        builder: (context, tick, _) {
          if (tick == null) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, box) => _number(tick, box.biggest),
          );
        },
      ),
    );
  }

  Widget _phoneNumber(CountInTick tick, Size box) {
    final fontSize = math.min(box.height * 0.45, box.width * 0.25);
    return Opacity(
      opacity: kCountInPhoneMaxOpacity * countInOpacityAt(tick.progress),
      child: Align(
        alignment: const Alignment(0.5, 0),
        child: Text(
          '${tick.remaining}',
          style: TextStyle(
            fontSize: fontSize,
            height: 1,
            fontWeight: FontWeight.w800,
            color: kCountInColor,
            decoration: TextDecoration.none,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _number(CountInTick tick, Size box) {
    if (widget.phone) return _phoneNumber(tick, box);
    final p = tick.progress;
    final fontSize = math.min(box.height * 0.62, box.width * 0.5);
    final sigma = fontSize * kCountInBlur * p;
    // O desfoque cobre a caixa inteira, não só o número: assim a borda
    // borrada (e o número já crescido) não é cortada.
    Widget number = SizedBox.expand(
      child: Center(
        child: Transform.scale(
          scale: 1 + kCountInGrowth * p,
          child: Text(
            '${tick.remaining}',
            style: TextStyle(
              fontSize: fontSize,
              height: 1,
              fontWeight: FontWeight.w800,
              color: kCountInColor,
              decoration: TextDecoration.none,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
    if (sigma > 0) {
      number = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.decal,
        ),
        child: number,
      );
    }
    return Opacity(opacity: countInOpacityAt(p), child: number);
  }
}
