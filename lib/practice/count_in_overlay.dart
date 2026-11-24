// Contagem regressiva por cima da partitura: no compasso a mais que antecede
// tudo o que anda no tempo (play, tempo real), o número de tempos que
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

import 'package:zywny_audio/metronome.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

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

class CountInOverlay extends StatelessWidget {
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
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => CountInCubit(),
    child: _CountInDriver(active: active, read: read, phone: phone),
  );
}

/// A contagem que a tela mostra agora (`null` fora dela).
class CountInState extends Equatable {
  const CountInState({this.tick});

  final CountInTick? tick;

  @override
  List<Object?> get props => [tick];
}

/// Guarda a contagem que a tela mostra. Quem a manda é o [_CountInDriver], a
/// cada quadro; um valor igual ao anterior não avisa a tela.
class CountInCubit extends Cubit<CountInState> {
  CountInCubit() : super(const CountInState());

  /// Mostra a contagem [tick] (ou tira, com `null`).
  void mostrar(CountInTick? tick) {
    if (isClosed) return;
    emit(CountInState(tick: tick));
  }
}

/// Dono do [Ticker] (o quadro): com a contagem ligada, pergunta
/// [CountInOverlay.read] a cada quadro e manda o resultado ao [CountInCubit].
/// Não guarda estado; o Ticker é objeto do framework.
class _CountInDriver extends StatefulWidget {
  const _CountInDriver({
    required this.active,
    required this.read,
    required this.phone,
  });

  final bool active;
  final CountInTick? Function() read;
  final bool phone;

  @override
  State<_CountInDriver> createState() => _CountInDriverState();
}

class _CountInDriverState extends State<_CountInDriver>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(
    (_) => context.read<CountInCubit>().mostrar(widget.read()),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_CountInDriver oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active == _ticker.isActive) return;
    final cubit = context.read<CountInCubit>();
    if (widget.active) {
      cubit.mostrar(widget.read());
      _ticker.start();
    } else {
      _ticker.stop();
      cubit.mostrar(null);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: _CountInView(phone: widget.phone));
}

/// O número da contagem, desenhado a partir do [CountInCubit].
class _CountInView extends StatelessWidget {
  const _CountInView({required this.phone});

  final bool phone;

  @override
  Widget build(BuildContext context) => BlocBuilder<CountInCubit, CountInState>(
    builder: (context, state) {
      final tick = state.tick;
      if (tick == null) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, box) => _number(tick, box.biggest),
      );
    },
  );

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
    if (phone) return _phoneNumber(tick, box);
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
