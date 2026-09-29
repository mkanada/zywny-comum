import 'package:flutter/material.dart';

import '../practice/hand.dart';
import 'theme.dart';
import 'widgets.dart';

/// Peças de tela do celular em paisagem — artboards `Celular*` do artefato
/// "zywny — interface de estudo": barra lateral de 84 px, selos de status do
/// treino e a gaveta "Opções de estudo" (botão ⋯). São só apresentação; quem
/// tem o estado (player, MIDI, motor de áudio) é `lib/main.dart`.

/// Largura da barra lateral (`width:84px` nos artboards).
const double kPhoneRailWidth = 84;

/// Abaixo desta largura (px lógicos) `lib/main.dart` usa o layout de celular;
/// a partir daqui, o banco de testes largo de sempre (desktop).
const double kPhoneLayoutMaxWidth = 1000;

class PhoneRail extends StatelessWidget {
  const PhoneRail({
    super.key,
    required this.playing,
    required this.onPlayPause,
    required this.measure,
    required this.totalMeasures,
    required this.tempoPercent,
    required this.handLabel,
    required this.onOptions,
    this.playIcon,
    this.playTooltip,
    this.onMeasureTap,
  });

  final bool playing;

  /// `null` desabilita o botão (nenhuma partitura pronta para tocar).
  final VoidCallback? onPlayPause;
  final Widget? playIcon;
  final String? playTooltip;

  /// Compasso atual (base 1) e total; `null` enquanto não há partitura.
  final int? measure;
  final int? totalMeasures;
  final VoidCallback? onMeasureTap;

  final int tempoPercent;
  final String handLabel;

  /// Andamento, mão e ⋯ abrem todos a mesma gaveta, como no artboard.
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kPhoneRailWidth,
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
      decoration: const BoxDecoration(
        color: kPanelSideBg,
        border: Border(left: BorderSide(color: kBorderPanel)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton.filled(
            tooltip: playTooltip ?? (playing ? 'Pausar' : 'Tocar'),
            onPressed: onPlayPause,
            style: IconButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(52, 52),
              maximumSize: const Size(52, 52),
            ),
            icon:
                playIcon ??
                Icon(playing ? Icons.pause : Icons.play_arrow, size: 24),
          ),
          _RailButton(
            top: measure == null ? '—' : '$measure',
            bottom: totalMeasures == null ? 'compasso' : 'de $totalMeasures',
            tooltip: 'Ir para compasso',
            onTap: onMeasureTap,
          ),
          _RailButton(
            top: '$tempoPercent%',
            bottom: 'andamento',
            tooltip: 'Andamento',
            onTap: onOptions,
          ),
          _RailButton(
            top: handLabel,
            bottom: 'mão',
            tooltip: 'Mão',
            onTap: onOptions,
          ),
          IconButton(
            tooltip: 'Mais opções',
            onPressed: onOptions,
            iconSize: 22,
            color: kIconQuiet,
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.top,
    required this.bottom,
    required this.tooltip,
    required this.onTap,
  });

  final String top;
  final String bottom;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                top,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                  color: kInk,
                ),
              ),
              Text(
                bottom,
                maxLines: 1,
                style: const TextStyle(fontSize: 10.5, color: kInkCaption),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selo azul "Esperando · mão dir." (`CelularTreino`).
class PhoneStatusPill extends StatelessWidget {
  const PhoneStatusPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: kAccentSoftBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: kAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kAccentDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Contadores do treino: acertos (verde) e erros (×).
///
/// O artefato tem ainda um terceiro, âmbar; ele só existe no modo tempo real
/// (notas fora do tempo, T03) — sem esse modo, o modo espera só acerta ou
/// erra, então o contador âmbar não é desenhado.
class PhoneCountersPill extends StatelessWidget {
  const PhoneCountersPill({
    super.key,
    required this.correct,
    required this.mistakes,
  });

  final int correct;
  final int mistakes;

  @override
  Widget build(BuildContext context) {
    const bold = TextStyle(fontWeight: FontWeight.w700, fontSize: 12);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: kLibraryCardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: kGoodColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text('$correct', style: bold),
          const SizedBox(width: 12),
          const Text(
            '×',
            style: TextStyle(
              color: kBadColor,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1,
            ),
          ),
          const SizedBox(width: 4),
          Text('$mistakes', style: bold),
        ],
      ),
    );
  }
}

/// Gaveta "Opções de estudo" (`CelularPainel`): 400 px à direita sobre um
/// véu, com o que o artefato pede — modo, mão e andamento — e, embaixo, [children] para o que só o app real tem (som,
/// monitor MIDI, layout…).
class PhoneOptionsDrawer extends StatelessWidget {
  const PhoneOptionsDrawer({
    super.key,
    required this.training,
    required this.onTrainingChanged,
    required this.hand,
    required this.onHandChanged,
    required this.tempoPercent,
    required this.onTempoChanged,
    required this.onClose,
    this.children = const [],
  });

  /// `false` = Ouvir, `true` = Espera. "Tempo real" (T03) ainda não existe
  /// no app, então não é oferecido.
  final bool training;
  final ValueChanged<bool> onTrainingChanged;
  final Hand hand;
  final ValueChanged<Hand> onHandChanged;
  final int tempoPercent;
  final ValueChanged<int> onTempoChanged;
  final VoidCallback onClose;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: const ColoredBox(color: kScrim),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 400,
          child: Material(
            color: kSurface,
            elevation: 8,
            child: SafeArea(
              left: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Opções de estudo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: kInk,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: onClose,
                          iconSize: 20,
                          color: kIconQuiet,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Section(
                              label: 'MODO',
                              child: Segmented<bool>(
                                value: training,
                                options: const [false, true],
                                labelOf: (t) => t ? 'Espera' : 'Ouvir',
                                onChanged: onTrainingChanged,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _Section(
                              label: 'MÃO',
                              child: Segmented<Hand>(
                                value: hand,
                                options: Hand.values,
                                labelOf: (h) => h.label,
                                onChanged: onHandChanged,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const _Caption('ANDAMENTO'),
                                Text(
                                  '$tempoPercent%',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: kInk,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: tempoPercent.toDouble().clamp(25, 150),
                              min: 25,
                              max: 150,
                              activeColor: kAccent,
                              onChanged: (v) => onTempoChanged(v.round()),
                            ),
                            ...children,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Linha de interruptor da gaveta (mesmo desenho de "Metrônomo" no artefato).
class PhoneToggleRow extends StatelessWidget {
  const PhoneToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;

  /// `null` deixa o interruptor desabilitado.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeTrackColor: kAccent),
        ],
      ),
    );
  }
}

/// Linha-botão da gaveta para o que não cabe num interruptor (abrir o
/// monitor MIDI, o painel de layout…).
class PhoneActionRow extends StatelessWidget {
  const PhoneActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Icon(icon, size: 20, color: kIconQuiet),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Cabeçalho de um bloco extra da gaveta ("AVANÇADO", "SOM"…).
class PhoneSectionLabel extends StatelessWidget {
  const PhoneSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 2),
    child: _Caption(text),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [_Caption(label), const SizedBox(height: 4), child],
  );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.7,
      color: kInkCaption,
    ),
  );
}
