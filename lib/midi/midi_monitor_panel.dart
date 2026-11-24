import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import 'package:zywny_midi/midi_device_manager.dart';

import 'midi_device_picker.dart';
import 'midi_monitor_cubit.dart';

import 'package:zywny_midi/midi_input_service.dart';

import 'piano_keyboard.dart';

/// Quantas mensagens recentes o painel mostra (M01, "O que fazer" #2).
const int kMidiMonitorHistory = 20;

/// Painel "Monitor MIDI" (M01): últimas [kMidiMonitorHistory] mensagens de
/// [input] e um teclado de 88 teclas acendendo as notas seguradas. Quem liga
/// o dispositivo é [showMidiDevicePicker] (o mesmo diálogo do ícone da
/// AppBar) — este painel só mostra.
///
/// As mensagens ficam no [MidiMonitorCubit], criado aqui; o painel em si não
/// guarda estado.
class MidiMonitorPanel extends StatelessWidget {
  const MidiMonitorPanel({
    super.key,
    required this.deviceManager,
    required this.input,
    required this.onClose,
    this.wrong,
    this.heldPitchOf,
  });

  final MidiDeviceManager deviceManager;
  final MidiInputService input;
  final VoidCallback onClose;

  /// Pitches errados do modo treino (T02), pintados em vermelho por cima de
  /// [held]. `null` fora do modo treino — o teclado volta a só acender o
  /// que está apertado.
  final ValueListenable<Set<int>>? wrong;

  /// Converte a altura que chegou na **escrita** (fase Q): o teclado desenhado
  /// mostra a tecla que a pessoa aperta, a mesma de [wrong]. `null` = as que
  /// chegam, sem conversão.
  final int Function(int received)? heldPitchOf;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          MidiMonitorCubit(notes: input.notes, limite: kMidiMonitorHistory),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 6,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const Divider(height: 1),
            _deviceLine(context),
            _keyboardPaint(context),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(child: _messagesArea(context)),
          ],
        ),
      ),
    );
  }

  /// O título ("Teclas que chegam") e os botões: trocar o dispositivo, fechar.
  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text('Teclas que chegam', style: theme.textTheme.titleSmall),
          ),
          IconButton(
            tooltip: 'Trocar dispositivo',
            onPressed: () => showMidiDevicePicker(context, deviceManager),
            icon: const Icon(Icons.piano, size: 20),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  /// O nome do teclado conectado (ou que nenhum está).
  Widget _deviceLine(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListenableBuilder(
        listenable: deviceManager.connected,
        builder: (context, _) {
          final device = deviceManager.connected.value;
          return Text(
            device == null
                ? 'nenhum dispositivo conectado'
                : 'conectado: ${device.name}',
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          );
        },
      ),
    );
  }

  /// O desenho do teclado, com as teclas apertadas e as erradas.
  Widget _keyboardPaint(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, constraints) => ValueListenableBuilder<Set<int>>(
          valueListenable: input.held,
          builder: (context, received, _) {
            final convert = heldPitchOf;
            final held = convert == null
                ? received
                : {for (final p in received) convert(p)};
            Widget paint(Set<int> wrongPitches) => CustomPaint(
              size: Size(constraints.maxWidth, 64),
              painter: PianoKeyboardPainter(
                held: held,
                heldColor: theme.colorScheme.primary,
                wrong: wrongPitches,
              ),
            );
            final erradas = wrong;
            if (erradas == null) return paint(const {});
            return ValueListenableBuilder<Set<int>>(
              valueListenable: erradas,
              builder: (context, wrongPitches, _) => paint(wrongPitches),
            );
          },
        ),
      ),
    );
  }

  /// As mensagens das teclas (ou a dica de tocar uma nota, sem nenhuma).
  Widget _messagesArea(BuildContext context) {
    return BlocSelector<MidiMonitorCubit, MidiMonitorState, List<PlayedNote>>(
      selector: (state) => state.messages,
      builder: (context, messages) {
        if (messages.isEmpty) {
          return Center(
            child: Text(
              'toque uma nota para ver aqui',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return ListView.builder(
          itemCount: messages.length,
          itemBuilder: (context, i) => _MessageRow(messages[i]),
        );
      },
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
