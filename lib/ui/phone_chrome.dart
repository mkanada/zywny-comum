import 'package:flutter/material.dart';

import '../practice/hand.dart';
import '../practice/study_mode.dart';
import 'side_panel.dart';
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

/// As chaves que o tutorial (`lib/tutorial/`) usa para apontar os botões da
/// barra lateral. Nulas fora dele: cada botão só leva a sua chave se houver.
class PhoneRailKeys {
  const PhoneRailKeys({
    this.play,
    this.listen,
    this.restart,
    this.measure,
    this.tempo,
    this.hand,
    this.options,
  });

  final GlobalKey? play;
  final GlobalKey? listen;
  final GlobalKey? restart;
  final GlobalKey? measure;
  final GlobalKey? tempo;
  final GlobalKey? hand;
  final GlobalKey? options;
}

class PhoneRail extends StatelessWidget {
  const PhoneRail({
    super.key,
    this.tourKeys,
    required this.playing,
    required this.onPlayPause,
    required this.measure,
    required this.totalMeasures,
    required this.tempoPercent,
    required this.handLabel,
    required this.onOptions,
    this.playIcon,
    this.playTooltip,
    this.onRestart,
    this.onMeasureTap,
    this.onListen,
    this.listening = false,
    this.stageTempo,
    this.stageTempoCaption = 'da etapa',
    this.stageHand,
    this.onStageTap,
  });

  /// Para o tutorial apontar os botões; `null` fora dele.
  final PhoneRailKeys? tourKeys;

  final bool playing;

  /// `null` desabilita o botão (nenhuma partitura pronta para tocar).
  final VoidCallback? onPlayPause;
  final Widget? playIcon;
  final String? playTooltip;

  /// Volta ao começo (da música, do trecho em repetição ou da etapa);
  /// `null` desabilita o botão.
  final VoidCallback? onRestart;

  /// Compasso atual (base 1) e total; `null` enquanto não há partitura.
  final int? measure;
  final int? totalMeasures;
  final VoidCallback? onMeasureTap;

  /// "Ouvir o trecho" da trilha (U03): `null` fora da trilha — sem botão.
  final VoidCallback? onListen;
  final bool listening;

  /// Modo trilha (U07): o andamento **da etapa** ("50%", ou "livre" no modo
  /// espera), só para ler — não abre nada — e sem o botão de mão, que a
  /// etapa decide. `null` = barra do treino livre.
  final String? stageTempo;
  final String stageTempoCaption;

  /// Mão da etapa (modo trilha), abreviada; `null` fora da trilha.
  final String? stageHand;

  /// Toque no andamento/mão da etapa: leva à lista de etapas, onde a etapa
  /// é escolhida — esses valores não se editam aqui, mas não ficam mudos.
  final VoidCallback? onStageTap;

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
            key: tourKeys?.play,
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
          if (onListen != null)
            IconButton(
              key: tourKeys?.listen,
              tooltip: listening ? 'Parar de ouvir' : 'Ouvir o trecho',
              onPressed: onListen,
              iconSize: 22,
              visualDensity: VisualDensity.compact,
              color: kAccentDark,
              icon: Icon(listening ? Icons.stop : Icons.hearing),
            ),
          IconButton(
            key: tourKeys?.restart,
            tooltip: 'Reiniciar',
            onPressed: onRestart,
            iconSize: 24,
            visualDensity: VisualDensity.compact,
            color: kInk,
            icon: const Icon(Icons.skip_previous),
          ),
          _RailButton(
            key: tourKeys?.measure,
            top: measure == null ? '—' : '$measure',
            bottom: totalMeasures == null ? 'compasso' : 'de $totalMeasures',
            tooltip: 'Ir para compasso',
            onTap: onMeasureTap,
          ),
          if (stageTempo case final tempo?) ...[
            if (stageHand case final hand?)
              _RailButton(
                key: tourKeys?.hand,
                top: hand,
                bottom: 'mão da etapa',
                tooltip: 'Mão da etapa — ver etapas',
                onTap: onStageTap,
              ),
            _RailButton(
              key: tourKeys?.tempo,
              top: tempo,
              bottom: stageTempoCaption,
              tooltip: 'Andamento da etapa — ver etapas',
              onTap: onStageTap,
            ),
          ] else ...[
            _RailButton(
              key: tourKeys?.tempo,
              top: '$tempoPercent%',
              bottom: 'andamento',
              tooltip: 'Andamento',
              onTap: onOptions,
            ),
            _RailButton(
              key: tourKeys?.hand,
              top: handLabel,
              bottom: 'mão',
              tooltip: 'Mão',
              onTap: onOptions,
            ),
          ],
          IconButton(
            key: tourKeys?.options,
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
    super.key,
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

/// Altura da faixa de título do celular ([PhoneTitleBar]).
const double kPhoneTitleBarHeight = 40;

/// Faixa do topo da partitura no celular: voltar, o número e o título do
/// hino e, à direita, o que estiver em [trailing] (os selos do treino).
///
/// O artboard `CelularEstudo` só tem o botão de voltar sobre a partitura; o
/// título vem da barra de `Main` (desktop) — Source Serif 4 semibold sobre o
/// fundo das barras — encolhido para uma linha, que a altura em paisagem é
/// pouca. É uma faixa própria, e não um texto por cima da página, para nunca
/// cobrir a primeira pauta.
class PhoneTitleBar extends StatelessWidget {
  const PhoneTitleBar({
    super.key,
    required this.number,
    required this.title,
    required this.onBack,
    this.center,
    this.trailing = const [],
    this.backKey,
  });

  /// Número do hinário; `null` sem hino aberto.
  final int? number;
  final String title;
  final VoidCallback onBack;

  /// Bloco entre o título e os selos (a etapa da trilha, U01); título e
  /// bloco dividem o espaço e cortam com reticências, nada estoura.
  final Widget? center;
  final List<Widget> trailing;

  /// Para o tutorial apontar o botão de voltar; `null` fora dele.
  final GlobalKey? backKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kPhoneTitleBarHeight,
      padding: const EdgeInsets.only(left: 6, right: 12),
      decoration: const BoxDecoration(
        color: kPanelSideBg,
        border: Border(bottom: BorderSide(color: kBorderPanel)),
      ),
      child: Row(
        children: [
          IconButton(
            key: backKey,
            tooltip: 'Voltar à biblioteca',
            onPressed: onBack,
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            color: kInkCaption,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          if (number case final number?) ...[
            Text(
              '$number',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: kInkCaption,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: serifDisplay(fontSize: 18),
            ),
          ),
          if (center case final center?) ...[
            const SizedBox(width: 12),
            Expanded(child: center),
          ],
          for (final widget in trailing) ...[const SizedBox(width: 8), widget],
        ],
      ),
    );
  }
}

/// Alto-falante da barra do título (U04): o estado do som de agora e um
/// toque para trocá-lo. [onPressed] `null` desabilita (treino em curso).
class PhoneSoundButton extends StatelessWidget {
  const PhoneSoundButton({
    super.key,
    required this.on,
    required this.tooltip,
    required this.onPressed,
    this.loading = false,
  });

  final bool on;
  final bool loading;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: loading ? null : onPressed,
      iconSize: 22,
      visualDensity: VisualDensity.compact,
      color: on ? kAccentDark : kInkCaption,
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(on ? Icons.volume_up : Icons.volume_off),
    );
  }
}

/// Aviso da trilha sem teclado conectado (U03): toque abre a lista de
/// dispositivos.
class PhoneKeyboardNotice extends StatelessWidget {
  const PhoneKeyboardNotice({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 210),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.piano_off, size: 18, color: kInkCaption),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Conecte o teclado para praticar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: kInkCaption),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Título da partitura na barra do desktop — o bloco central da barra de
/// `Main.dc.html`: título em Source Serif 4 20/600 e uma linha de legenda.
class ScoreTitle extends StatelessWidget {
  const ScoreTitle({super.key, required this.title, this.caption});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: serifDisplay(fontSize: 20).copyWith(height: 1.1),
        ),
        if (caption case final caption?) ...[
          const SizedBox(height: 1),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: kInkCaption),
          ),
        ],
      ],
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

/// Selo de acertos do treino com resultado (U05): a porcentagem corrente,
/// na conta do resumo da etapa, e a [goalPercent] quando há meta. Verde a
/// partir da meta, âmbar abaixo; neutro sem meta ou sem nada avaliado ("—").
class PhoneScorePill extends StatelessWidget {
  const PhoneScorePill({
    super.key,
    required this.hits,
    required this.total,
    this.goalPercent,
  });

  final int hits;
  final int total;
  final int? goalPercent;

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? null : hits * 100 ~/ total;
    final goal = goalPercent;
    final color = percent == null || goal == null
        ? kInk
        : (hits * 100 >= goal * total ? kGoodColor : kOkColor);
    const tabular = [FontFeature.tabularFigures()];
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: kLibraryCardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: percent == null ? '—' : '$percent%',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: color,
                fontFeatures: tabular,
              ),
            ),
            if (goal != null)
              TextSpan(
                text: ' · meta $goal%',
                style: const TextStyle(
                  fontSize: 12,
                  color: kInkCaption,
                  fontFeatures: tabular,
                ),
              ),
          ],
        ),
        maxLines: 1,
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
    required this.mode,
    required this.onModeChanged,
    required this.hand,
    required this.onHandChanged,
    required this.tempoPercent,
    required this.onTempoChanged,
    required this.onClose,
    this.trailMode = false,
    this.top = const [],
    this.children = const [],
  });

  /// O modo de estudo do treino livre (U11): um seletor só, com uma linha
  /// explicando o escolhido. [onModeChanged] `null` o desabilita (treino
  /// rodando).
  final StudyMode mode;
  final ValueChanged<StudyMode>? onModeChanged;
  final Hand hand;
  final ValueChanged<Hand> onHandChanged;
  final int tempoPercent;
  final ValueChanged<int> onTempoChanged;
  final VoidCallback onClose;

  /// Na trilha o modo, a mão e o andamento são da etapa: a gaveta não os
  /// mostra (e abre pelo que vale: [top] e [children]).
  final bool trailMode;

  /// O que abre a gaveta, antes de modo/mão/andamento (a seção da trilha).
  final List<Widget> top;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PhoneSidePanel(
      title: 'Opções de estudo',
      onClose: onClose,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...top,
            if (!trailMode) ...[
              _Section(
                label: 'MODO',
                child: IgnorePointer(
                  ignoring: onModeChanged == null,
                  child: Opacity(
                    opacity: onModeChanged == null ? 0.5 : 1,
                    child: Segmented<StudyMode>(
                      value: mode,
                      options: StudyMode.values,
                      labelOf: (m) => m.label,
                      onChanged: (m) => onModeChanged?.call(m),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  mode.explanation,
                  style: const TextStyle(fontSize: 12, color: kInkCaption),
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
                    style: const TextStyle(fontSize: 13, color: kInk),
                  ),
                ],
              ),
              Slider(
                value: tempoPercent.toDouble().clamp(25, 150),
                min: 25,
                max: 150,
                onChanged: (v) => onTempoChanged(v.round()),
              ),
            ],
            ...children,
          ],
        ),
      ),
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
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Slider com rótulo e valor da gaveta (mesmo desenho de "ANDAMENTO"):
/// [onChanged] a cada passo, [onChangeEnd] ao soltar — para o que só vale a
/// pena aplicar uma vez (regravar a partitura).
class PhoneSliderRow extends StatelessWidget {
  const PhoneSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.formatValue,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double value) formatValue;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Caption(label),
          Text(
            formatValue(value),
            style: const TextStyle(fontSize: 13, color: kInk),
          ),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    ],
  );
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
