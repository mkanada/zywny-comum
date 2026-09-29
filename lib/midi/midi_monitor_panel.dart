import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'midi_device_manager.dart';
import 'midi_device_picker.dart';
import 'midi_input_service.dart';
import 'piano_keyboard.dart';

/// Quantas mensagens recentes o painel mostra (M01, "O que fazer" #2).
const int kMidiMonitorHistory = 20;

/// Painel "Monitor MIDI" (M01): últimas [kMidiMonitorHistory] mensagens de
/// [input] e um teclado de 88 teclas acendendo as notas seguradas. Quem liga
/// o dispositivo é [showMidiDevicePicker] (o mesmo diálogo do ícone da
/// AppBar) — este painel só mostra.
class MidiMonitorPanel extends StatefulWidget {
  const MidiMonitorPanel({
    super.key,
    required this.deviceManager,
    required this.input,
    required this.onClose,
    this.wrong,
  });

  final MidiDeviceManager deviceManager;
  final MidiInputService input;
  final VoidCallback onClose;

  /// Pitches errados do modo treino (T02), pintados em vermelho por cima de
  /// [held]. `null` fora do modo treino — o teclado volta a só acender o
  /// que está apertado.
  final ValueListenable<Set<int>>? wrong;

  @override
  State<MidiMonitorPanel> createState() => _MidiMonitorPanelState();
}

class _MidiMonitorPanelState extends State<MidiMonitorPanel> {
  final List<PlayedNote> _messages = [];
  StreamSubscription<PlayedNote>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.input.notes.listen((note) {
      setState(() {
        _messages.insert(0, note);
        if (_messages.length > kMidiMonitorHistory) _messages.removeLast();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

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
                  child: Text(
                    'Monitor MIDI',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Trocar dispositivo',
                  onPressed: () =>
                      showMidiDevicePicker(context, widget.deviceManager),
                  icon: const Icon(Icons.piano, size: 20),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListenableBuilder(
              listenable: widget.deviceManager.connected,
              builder: (context, _) {
                final device = widget.deviceManager.connected.value;
                return Text(
                  device == null
                      ? 'nenhum dispositivo conectado'
                      : 'conectado: ${device.name}',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  ValueListenableBuilder<Set<int>>(
                    valueListenable: widget.input.held,
                    builder: (context, held, _) {
                      final wrong = widget.wrong;
                      Widget paint(Set<int> wrongPitches) => CustomPaint(
                        size: Size(constraints.maxWidth, 64),
                        painter: PianoKeyboardPainter(
                          held: held,
                          heldColor: theme.colorScheme.primary,
                          wrong: wrongPitches,
                        ),
                      );
                      if (wrong == null) return paint(const {});
                      return ValueListenableBuilder<Set<int>>(
                        valueListenable: wrong,
                        builder: (context, wrongPitches, _) =>
                            paint(wrongPitches),
                      );
                    },
                  ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'toque uma nota para ver aqui',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _MessageRow(_messages[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow(this.note);

  final PlayedNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(
        note.on ? Icons.volume_up : Icons.volume_off,
        size: 18,
        color: note.on ? theme.colorScheme.primary : null,
      ),
      title: Text(
        '${_noteName(note.pitch)}  vel=${note.velocity}  ch=${note.channel}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        '${note.atSeconds.toStringAsFixed(3)}s',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

const List<String> _kNoteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// Nome científico da nota (C4 = dó central = MIDI 60), para o monitor.
String _noteName(int pitch) {
  final octave = (pitch ~/ 12) - 1;
  return '${_kNoteNames[pitch % 12]}$octave';
}
