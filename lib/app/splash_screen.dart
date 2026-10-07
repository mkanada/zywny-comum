import 'dart:async';

import 'package:flutter/material.dart';

/// Splash "C — Varsóvia, 1816" do artefato "Zywny — Ícone e Splash": vinho,
/// o Z itálico do ícone, o lema e a homenagem a Wojciech Żywny. O artefato
/// desenha em retrato; como o app roda em paisagem no celular, aqui o Z fica
/// ao lado do texto quando a tela é mais larga que alta.
const kSplashWine = Color(0xFF5A1E2B);
const kSplashCream = Color(0xFFF4EEE1);
const kSplashGold = Color(0xFFC8A45A);
const _kSplashSoft = Color(0xFFE6DFD0);
const _kSplashCredit = Color(0xFFD9D2C3);

const _serif = 'Cormorant Garamond';
const _sans = 'Instrument Sans';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kSplashWine,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final landscape = box.maxWidth > box.maxHeight;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                36,
                landscape ? 20 : 88,
                36,
                landscape ? 20 : 56,
              ),
              child: Column(
                children: [
                  const _Label(),
                  Expanded(
                    child: Center(
                      child: landscape
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _MonogramZ(size: 170),
                                const SizedBox(width: 44),
                                Flexible(child: _Words(landscape: true)),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _MonogramZ(size: 200),
                                const SizedBox(height: 20),
                                _Words(landscape: false),
                              ],
                            ),
                    ),
                  ),
                  const _Credit(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label();

  @override
  Widget build(BuildContext context) => const Text(
    'VARSÓVIA · 1816',
    style: TextStyle(
      fontFamily: _sans,
      fontWeight: FontWeight.w500,
      fontSize: 13,
      letterSpacing: 4,
      color: kSplashGold,
      decoration: TextDecoration.none,
    ),
  );
}

class _MonogramZ extends StatelessWidget {
  const _MonogramZ({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Text(
    'Z',
    style: TextStyle(
      fontFamily: _serif,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
      fontSize: size,
      height: 0.8,
      color: kSplashCream,
      decoration: TextDecoration.none,
    ),
  );
}

class _Words extends StatelessWidget {
  const _Words({required this.landscape});

  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final align = landscape
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    final textAlign = landscape ? TextAlign.start : TextAlign.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        const Text(
          'Zywny',
          style: TextStyle(
            fontFamily: _serif,
            fontWeight: FontWeight.w600,
            fontSize: 52,
            letterSpacing: 1,
            height: 1,
            color: kSplashCream,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 48,
          height: 3,
          decoration: BoxDecoration(
            color: kSplashGold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Todo grande pianista começou na primeira tecla.',
          textAlign: textAlign,
          style: const TextStyle(
            fontFamily: _serif,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
            fontSize: 21,
            height: 1.35,
            color: _kSplashSoft,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit();

  @override
  Widget build(BuildContext context) => const Text(
    'Inspirado em Wojciech Żywny, o primeiro professor de Chopin',
    textAlign: TextAlign.center,
    style: TextStyle(
      fontFamily: _sans,
      fontWeight: FontWeight.w500,
      fontSize: 13,
      height: 1.5,
      color: _kSplashCredit,
      decoration: TextDecoration.none,
    ),
  );
}

/// Mostra [SplashScreen] por cima de [child] por [duration] e some com um
/// fade. O app já monta por baixo (MIDI, medição da caixa da partitura), só
/// não recebe toques até a splash sair. Com [enabled] `false` (testes), não
/// há splash nem timer.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({
    super.key,
    required this.child,
    this.enabled = true,
    this.duration = const Duration(milliseconds: 1800),
  });

  final Widget child;
  final bool enabled;
  final Duration duration;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> {
  late bool _showing = widget.enabled;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_showing) {
      _timer = Timer(widget.duration, () {
        if (mounted) setState(() => _showing = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          ignoring: !_showing,
          child: AnimatedOpacity(
            opacity: _showing ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: const SplashScreen(),
          ),
        ),
      ],
    );
  }
}
