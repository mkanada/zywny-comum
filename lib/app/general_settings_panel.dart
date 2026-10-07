import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:score_bridge/score_bridge.dart' show kDefaultBarColor;

import '../audio/soundfont_store.dart';
import '../course/course_installer.dart';
import '../course/course_store.dart';
import '../music/note_names.dart' show NoteNaming;
import '../midi/midi_device_manager.dart';
import '../midi/midi_device_picker.dart';
import '../practice/practice_colors.dart';
import '../trail/trail_stage.dart' show kTrailSpeeds;
import '../trail/trail_widgets.dart';
import '../library/library_installer.dart';
import '../library/library_store.dart';
import '../library/library_term_scope.dart';
import '../ui/theme.dart';
import '../settings/app_settings.dart';
import '../settings/color_picker.dart';
import 'courses_section.dart';
import 'libraries_section.dart';

/// Abre o seletor de arquivos para um `.sf2` e devolve os bytes; `null` se
/// o usuário cancelou. No Android o filtro por extensão volta vazio (o SAF
/// casa por tipo MIME), então lá não se filtra.
Future<Uint8List?> pickSoundFontBytes() async {
  final file = await openFile(
    acceptedTypeGroups: [
      !kIsWeb && Platform.isAndroid
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
    this.libraries,
    this.courses,
  });

  final AppSettings settings;
  final MidiDeviceManager midiDeviceManager;

  /// O usuário escolheu um `.sf2` próprio (senão vale o TimGM6mb embutido).
  final bool customSoundFont;
  final VoidCallback onChooseSoundFont;
  final VoidCallback onResetSoundFont;
  final VoidCallback onClose;
  final LiveSettingsActions? live;

  /// A seção Bibliotecas — só nas configurações abertas pela biblioteca;
  /// com uma partitura aberta, trocar de biblioteca não faz sentido.
  final Widget? libraries;

  /// A seção Cursos (I04) — junto da de bibliotecas, pelo mesmo motivo.
  final Widget? courses;

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
                        'valem para ${LibraryTermScope.of(context).todos} '
                        '${LibraryTermScope.of(context).os} '
                        '${LibraryTermScope.of(context).plural}',
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
      ?libraries,
      ?courses,
      const _Header('Som'),
      SwitchListTile(
        dense: true,
        title: const Text('Som'),
        subtitle: const Text('o app toca a música'),
        value: settings.soundOn,
        onChanged: busy ? null : (v) => settings.soundOn = v,
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text(
          'O som sai por',
          style: TextStyle(fontSize: 12, color: kInkCaption),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: SegmentedButton<SoundOutput>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: SoundOutput.appSynth,
              icon: Icon(Icons.graphic_eq, size: 18),
              label: Text('Celular'),
            ),
            ButtonSegment(
              value: SoundOutput.midiKeyboard,
              icon: Icon(Icons.piano, size: 18),
              label: Text('Teclado'),
            ),
          ],
          selected: {settings.output},
          onSelectionChanged: busy ? null : (s) => settings.output = s.first,
        ),
      ),
      if (toMidi)
        SwitchListTile(
          dense: true,
          title: const Text('Trocar o timbre do teclado'),
          subtitle: const Text('usa o instrumento da partitura'),
          value: settings.useScoreInstruments,
          onChanged: (v) => settings.useScoreInstruments = v,
        ),
      // Na Web não há onde guardar o .sf2 escolhido (W04): só o padrão.
      if (!kIsWeb)
        ListTile(
          dense: true,
          leading: const Icon(Icons.library_music, size: 20),
          title: const Text('Timbre do piano'),
          subtitle: Text(customSoundFont ? 'personalizado' : 'padrão'),
          trailing: const _RowAction('Trocar'),
          onTap: busy ? null : onChooseSoundFont,
        ),
      if (customSoundFont)
        ListTile(
          dense: true,
          leading: const Icon(Icons.restore, size: 20),
          title: const Text('Voltar ao timbre padrão'),
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
        trailing: _RowAction(device == null ? 'Conectar' : 'Trocar'),
        onTap: () =>
            unawaited(showMidiDevicePicker(context, midiDeviceManager)),
      ),
      if (live != null) ...[
        SwitchListTile(
          dense: true,
          title: const Text('Ouvir o que eu toco pelo celular'),
          subtitle: const Text('para teclado sem som próprio'),
          value: live.monitorOn,
          onChanged: busy ? null : live.onMonitorChanged,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.timer_outlined, size: 20),
          title: const Text('Atraso do teclado'),
          subtitle: Text(
            live.inputLatencyMs == 0
                ? 'não ajustado'
                : '${live.inputLatencyMs.round()} ms',
          ),
          trailing: const _RowAction('Ajustar'),
          enabled: device != null,
          onTap: live.onCalibrate,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.keyboard_alt_outlined, size: 20),
          title: const Text('Ver as teclas que chegam'),
          onTap: live.onOpenMidiPanel,
        ),
      ],
      const _Header('Texto'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nomes das notas',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            SegmentedButton<NoteNaming>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: NoteNaming.latin, label: Text('Dó-Ré-Mi')),
                ButtonSegment(value: NoteNaming.letters, label: Text('C-D-E')),
              ],
              selected: {settings.noteNaming},
              onSelectionChanged: (s) => settings.noteNaming = s.first,
            ),
          ],
        ),
      ),
      const _Header('Transpor'),
      SwitchListTile(
        dense: true,
        title: const Text('Abrir as músicas já sem acidentes'),
        subtitle: const Text('Cada música pode voltar ao original na gaveta'),
        value: settings.transposeByDefault,
        onChanged: (v) => settings.transposeByDefault = v,
      ),
      const _Header('Trilha de estudo'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TrailNSelector(
          value: settings.trailMeasures,
          max: 20,
          onChanged: (v) => unawaited(_changeTrailN(context, settings, v)),
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          'Etapas de cada trecho (arraste para mudar a ordem)',
          style: TextStyle(fontSize: 13, color: kInkCaption),
        ),
      ),
      // Arrastar pela alça muda a ordem; a caixa liga e desliga a etapa.
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (from, to) {
          final order = [...settings.trailPhaseOrder];
          order.insert(to, order.removeAt(from));
          settings.trailPhaseOrder = order;
        },
        children: [
          for (final (i, phase) in settings.trailPhaseOrder.indexed)
            CheckboxListTile(
              key: ValueKey(phase),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(phase.label),
              value: settings.trailPhases.contains(phase),
              // A última marcada não sai: a trilha precisa de alguma etapa.
              onChanged:
                  settings.trailPhases.length == 1 &&
                      settings.trailPhases.contains(phase)
                  ? null
                  : (on) => settings.trailPhases = on == true
                        ? {...settings.trailPhases, phase}
                        : ({...settings.trailPhases}..remove(phase)),
              secondary: ReorderableDragStartListener(
                index: i,
                child: const Icon(Icons.drag_handle, color: kInkCaption),
              ),
            ),
        ],
      ),
      _SliderRow(
        label: 'Margem do tempo (no andamento original)',
        value: settings.rhythmToleranceMs,
        min: kMinRhythmToleranceMs,
        max: kMaxRhythmToleranceMs,
        step: 5,
        formatValue: (v) => '±${v.round()} ms',
        onChanged: (v) => settings.rhythmToleranceMs = v,
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Quanto a nota pode sair antes ou depois e ainda contar como certa. '
          'Mais devagar, a margem cresce junto: a 50%, vale o dobro.',
          style: TextStyle(fontSize: 12, color: kInkCaption),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Andamentos no ritmo',
              style: TextStyle(fontSize: 13, color: kInkCaption),
            ),
            for (final speed in kTrailSpeeds)
              FilterChip(
                label: Text('${(speed * 100).round()}%'),
                selected: settings.trailSpeeds.contains(speed),
                onSelected:
                    settings.trailSpeeds.length == 1 &&
                        settings.trailSpeeds.contains(speed)
                    ? null
                    : (on) => settings.trailSpeeds = on
                          ? {...settings.trailSpeeds, speed}
                          : ({...settings.trailSpeeds}..remove(speed)),
              ),
          ],
        ),
      ),
      const _Header('Cores'),
      _ColorRow(
        label: 'Nota certa',
        hint: 'e a nota que soa ao ouvir',
        value: settings.highlightColor,
        defaultValue: kPracticeCorrectColor,
        onChanged: (c) => settings.highlightColor = c,
      ),
      _ColorRow(
        label: 'Nota esperada',
        hint: 'a que o app aguarda você tocar',
        value: settings.practicePendingColor,
        defaultValue: kPracticePendingColor,
        onChanged: (c) => settings.practicePendingColor = c,
      ),
      _ColorRow(
        label: 'Nota errada',
        hint: 'pisca na nota esperada mais próxima',
        value: settings.practiceWrongColor,
        defaultValue: kPracticeWrongColor,
        onChanged: (c) => settings.practiceWrongColor = c,
      ),
      _ColorRow(
        label: 'Barra de virada de página',
        hint: 'a barra que varre a página',
        value: settings.barColor,
        defaultValue: kDefaultBarColor,
        onChanged: (c) => settings.barColor = c,
      ),
      _SliderRow(
        label: 'Brilho em volta da nota',
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

/// Ação à direita de uma linha das configurações ("Trocar", "Conectar",
/// "Ajustar"): inicial maiúscula e cor de destaque, para ler como botão. A
/// linha inteira continua sendo o alvo do toque.
class _RowAction extends StatelessWidget {
  const _RowAction(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: kAccent,
    ),
  );
}

/// Troca o N geral com aviso: os hinos sem N próprio recomeçam a trilha
/// (cada um é descartado ao abrir, em `_setupTrail`).
Future<void> _changeTrailN(
  BuildContext context,
  AppSettings settings,
  int value,
) async {
  if (value == settings.trailMeasures) return;
  final term = LibraryTermScope.of(context);
  final ok = await confirmTrailReset(
    context,
    title: 'Mudar o tamanho dos trechos?',
    message:
        '${term.os[0].toUpperCase()}${term.os.substring(1)} ${term.plural} '
        'que usam o padrão recomeçam a trilha do começo.',
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
    this.libraryStore,
    this.pickLibraryFile = pickLibraryBytes,
    this.courseStore,
    this.onOpenDraft,
  });

  final AppSettings settings;
  final MidiDeviceManager midiDeviceManager;
  final SoundFontStore soundFonts;

  /// As bibliotecas instaladas (a seção Bibliotecas); `null` não mostra a
  /// seção.
  final LibraryStore? libraryStore;
  final Future<Uint8List?> Function() pickLibraryFile;

  /// Os cursos instalados (a seção Cursos, I04); `null` não mostra a seção.
  final CourseStore? courseStore;

  /// I12: abrir a pasta como rascunho (a `LibraryScreen` dona do rascunho
  /// entrega o abrir dela); `null` esconde o item.
  final VoidCallback? onOpenDraft;

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

  /// Instala um `.zywny` (biblioteca ou curso, I04) e avisa; a lista da
  /// seção acompanha sozinha (os stores avisam quem escuta).
  Future<void> _installPackage() async {
    final courses = widget.courseStore;
    final libraries = widget.libraryStore;
    if (courses == null) return;
    if (libraries == null) {
      await installCourseFromFile(
        context,
        courses,
        pick: widget.pickLibraryFile,
      );
    } else {
      await installPackageFromFile(
        context,
        libraries,
        courses,
        pick: widget.pickLibraryFile,
      );
    }
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
                libraries: widget.libraryStore == null
                    ? null
                    : LibrariesSection(
                        store: widget.libraryStore!,
                        onInstall: () => unawaited(
                          installLibraryFromFile(
                            context,
                            widget.libraryStore!,
                            pick: widget.pickLibraryFile,
                          ),
                        ),
                      ),
                courses: widget.courseStore == null
                    ? null
                    : CoursesSection(
                        store: widget.courseStore!,
                        onInstall: () => unawaited(_installPackage()),
                        onOpenDraft: widget.onOpenDraft,
                      ),
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
    this.step = 0.1,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
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
              divisions: ((max - min) / step).round(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
