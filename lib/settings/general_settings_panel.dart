import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:score_bridge/score_bridge.dart' show kDefaultBarColor;

import '../audio/soundfont_store.dart';
import '../midi/midi_device_manager.dart';
import '../midi/midi_device_picker.dart';
import '../practice/practice_colors.dart';
import '../trail/trail_widgets.dart';
import 'app_settings.dart';
import 'color_picker.dart';

/// Abre o seletor de arquivos para um `.sf2` e devolve os bytes; `null` se
/// o usuário cancelou. No Android o filtro por extensão volta vazio (o SAF
/// casa por tipo MIME), então lá não se filtra.
Future<Uint8List?> pickSoundFontBytes() async {
  final file = await openFile(
    acceptedTypeGroups: [
      Platform.isAndroid
          ? const XTypeGroup(label: 'soundfont')
          : const XTypeGroup(label: 'soundfont', extensions: ['sf2']),
    ],
  );
  return file?.readAsBytes();
}

/// O que só existe com uma partitura aberta — o motor de áudio ligado, o
/// monitor MIDI, a calibração — e que por isso a tela de partitura entrega
/// ao painel. Aberto pela biblioteca, o painel fica sem estas linhas.
@immutable
class LiveSettingsActions {
  const LiveSettingsActions({
    required this.busy,
    required this.monitorOn,
    required this.onMonitorChanged,
    required this.inputLatencyMs,
    required this.onCalibrate,
    required this.onOpenMidiPanel,
  });

  /// O motor de áudio está abrindo (carregando o `.sf2`): som e monitor
  /// esperam.
  final bool busy;

  /// Monitor MIDI (M02): o teclado soa pelo app — preferência guardada por
  /// dispositivo.
  final bool monitorOn;
  final ValueChanged<bool> onMonitorChanged;

  final double inputLatencyMs;
  final VoidCallback onCalibrate;
  final VoidCallback onOpenMidiPanel;
}

/// Painel das configurações **gerais** — som, teclado MIDI e cores: o que
/// vale para qualquer hino. (O que é de um hino só está no `LayoutPanel`.)
///
/// Tudo o que é valor mora em [settings], que grava cada mudança na hora;
/// quem precisa reagir (a tela de partitura) escuta o próprio [settings].
class GeneralSettingsPanel extends StatelessWidget {
  const GeneralSettingsPanel({
    super.key,
    required this.settings,
    required this.midiDeviceManager,
    required this.customSoundFont,
    required this.onChooseSoundFont,
    required this.onResetSoundFont,
    required this.onClose,
    this.live,
  });

  final AppSettings settings;
  final MidiDeviceManager midiDeviceManager;

  /// O usuário escolheu um `.sf2` próprio (senão vale o TimGM6mb embutido).
  final bool customSoundFont;
  final VoidCallback onChooseSoundFont;
  final VoidCallback onResetSoundFont;
  final VoidCallback onClose;
  final LiveSettingsActions? live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configurações gerais',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        'valem para todos os hinos',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                settings,
                midiDeviceManager.connected,
              ]),
              builder: (context, _) => ListView(children: _rows(context)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _rows(BuildContext context) {
    final live = this.live;
    final busy = live?.busy ?? false;
    final device = midiDeviceManager.connected.value;
    final toMidi = settings.output == SoundOutput.midiKeyboard;
    return [
      const _Header('Som'),
      SwitchListTile(
        dense: true,
        title: const Text('Som do app'),
        subtitle: const Text(
          'toca a partitura; desligado, só destaca as notas',
        ),
        value: settings.soundOn,
        onChanged: busy ? null : (v) => settings.soundOn = v,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: SegmentedButton<SoundOutput>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: SoundOutput.appSynth,
              icon: Icon(Icons.graphic_eq, size: 18),
              label: Text('Sintetizador'),
            ),
            ButtonSegment(
              value: SoundOutput.midiKeyboard,
              icon: Icon(Icons.piano, size: 18),
              label: Text('Teclado MIDI'),
            ),
          ],
          selected: {settings.output},
          onSelectionChanged: busy ? null : (s) => settings.output = s.first,
        ),
      ),
      if (toMidi)
        SwitchListTile(
          dense: true,
          title: const Text('Instrumentos da partitura'),
          subtitle: const Text('manda Program Change ao teclado'),
          value: settings.useScoreInstruments,
          onChanged: (v) => settings.useScoreInstruments = v,
        ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.library_music, size: 20),
        title: const Text('Soundfont do sintetizador'),
        subtitle: Text(customSoundFont ? 'personalizado' : 'TimGM6mb (padrão)'),
        trailing: const Text('trocar'),
        onTap: busy ? null : onChooseSoundFont,
      ),
      if (customSoundFont)
        ListTile(
          dense: true,
          leading: const Icon(Icons.restore, size: 20),
          title: const Text('Voltar ao soundfont padrão'),
          onTap: busy ? null : onResetSoundFont,
        ),
      const _Header('Teclado MIDI'),
      ListTile(
        dense: true,
        leading: Icon(
          device == null ? Icons.piano_outlined : Icons.piano,
          size: 20,
        ),
        title: const Text('Teclado MIDI'),
        subtitle: Text(device?.name ?? 'nenhum conectado'),
        trailing: Text(device == null ? 'Conectar' : 'Trocar'),
        onTap: () =>
            unawaited(showMidiDevicePicker(context, midiDeviceManager)),
      ),
      if (live != null) ...[
        SwitchListTile(
          dense: true,
          title: const Text('Monitor MIDI'),
          subtitle: const Text('o teclado soa pelo app (teclado sem som)'),
          value: live.monitorOn,
          onChanged: busy ? null : live.onMonitorChanged,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.timer_outlined, size: 20),
          title: const Text('Latência do teclado'),
          subtitle: Text(
            live.inputLatencyMs == 0
                ? 'não calibrada'
                : '${live.inputLatencyMs.round()} ms',
          ),
          trailing: const Text('calibrar'),
          enabled: device != null,
          onTap: live.onCalibrate,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.keyboard_alt_outlined, size: 20),
          title: const Text('Painel do monitor MIDI'),
          onTap: live.onOpenMidiPanel,
        ),
      ],
      const _Header('Trilha de estudo'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TrailNSelector(
          value: settings.trailMeasures,
          max: 20,
          onChanged: (v) => unawaited(_changeTrailN(context, settings, v)),
        ),
      ),
      const _Header('Cores'),
      _ColorRow(
        label: 'Nota destacada',
        hint: 'na reprodução e, no treino, a nota certa',
        value: settings.highlightColor,
        defaultValue: kPracticeCorrectColor,
        onChanged: (c) => settings.highlightColor = c,
      ),
      _ColorRow(
        label: 'Treino: nota em espera',
        hint: 'a que o app aguarda você tocar',
        value: settings.practicePendingColor,
        defaultValue: kPracticePendingColor,
        onChanged: (c) => settings.practicePendingColor = c,
      ),
      _ColorRow(
        label: 'Treino: nota errada',
        hint: 'pisca na nota esperada mais próxima',
        value: settings.practiceWrongColor,
        defaultValue: kPracticeWrongColor,
        onChanged: (c) => settings.practiceWrongColor = c,
      ),
      _ColorRow(
        label: 'Haste de virada',
        hint: 'a barra que varre a página',
        value: settings.barColor,
        defaultValue: kDefaultBarColor,
        onChanged: (c) => settings.barColor = c,
      ),
      _SliderRow(
        label: 'Largura do halo',
        value: settings.haloWidth,
        min: 0,
        max: 3,
        formatValue: (v) => v <= 0 ? 'desligado' : '${v.toStringAsFixed(1)}×',
        onChanged: (v) => settings.haloWidth = v,
      ),
      const SizedBox(height: 12),
    ];
  }
}

/// Troca o N geral com aviso: os hinos sem N próprio recomeçam a trilha
/// (cada um é descartado ao abrir, em `_setupTrail`).
Future<void> _changeTrailN(
  BuildContext context,
  AppSettings settings,
  int value,
) async {
  if (value == settings.trailMeasures) return;
  final ok = await confirmTrailReset(
    context,
    title: 'Mudar o padrão?',
    message: 'Os hinos sem N próprio recomeçam a trilha.',
    confirmLabel: 'Mudar',
  );
  if (!ok) return;
  settings.trailMeasures = value;
}

/// As configurações gerais abertas pela biblioteca, em tela cheia: sem
/// partitura aberta não há motor de áudio, então trocar o soundfont aqui só
/// o guarda (a próxima partitura já abre com ele).
class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({
    super.key,
    required this.settings,
    required this.midiDeviceManager,
    this.soundFonts = const SoundFontStore(),
  });

  final AppSettings settings;
  final MidiDeviceManager midiDeviceManager;
  final SoundFontStore soundFonts;

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  bool _custom = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final custom = await widget.soundFonts.hasCustom();
    if (mounted) setState(() => _custom = custom);
  }

  Future<void> _choose() async {
    try {
      final bytes = await pickSoundFontBytes();
      if (bytes == null) return;
      await widget.soundFonts.saveCustom(bytes);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('não consegui usar esse soundfont ($e)')),
      );
    }
    await _refresh();
  }

  Future<void> _reset() async {
    await widget.soundFonts.clearCustom();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: GeneralSettingsPanel(
                settings: widget.settings,
                midiDeviceManager: widget.midiDeviceManager,
                customSoundFont: _custom,
                onChooseSoundFont: () => unawaited(_choose()),
                onResetSoundFont: () => unawaited(_reset()),
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

/// Uma cor das configurações: o nome, para que serve e a amostra; o toque
/// abre o seletor ([showColorPicker]).
class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.defaultValue,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final Color value;
  final Color defaultValue;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(hint),
      trailing: Container(
        width: 44,
        height: 28,
        decoration: BoxDecoration(
          color: value,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black26),
        ),
      ),
      onTap: () async {
        final picked = await showColorPicker(
          context,
          title: label,
          initial: value,
          defaultColor: defaultValue,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// A generic labelled slider for a setting that isn't a Verovio option (so
/// doesn't fit [LayoutOption]/[_OptionRow]) and applies immediately — no
/// `onCommit`/render step.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.formatValue,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double value) formatValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: style)),
              Text(formatValue(value), style: style),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) / 0.1).round(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
