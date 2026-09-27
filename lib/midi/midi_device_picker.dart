import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

import 'midi_device_manager.dart';

/// Ícone de dispositivo MIDI para a AppBar (M01): mostra se algo está
/// conectado e abre [showMidiDevicePicker] ao tocar.
class MidiDevicePickerButton extends StatelessWidget {
  const MidiDevicePickerButton({super.key, required this.deviceManager});

  final MidiDeviceManager deviceManager;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: deviceManager.connected,
      builder: (context, _) {
        final device = deviceManager.connected.value;
        return IconButton(
          tooltip: device == null
              ? 'Escolher dispositivo MIDI'
              : 'MIDI: ${device.name}',
          onPressed: () => showMidiDevicePicker(context, deviceManager),
          icon: Icon(device == null ? Icons.piano_outlined : Icons.piano),
        );
      },
    );
  }
}

/// Diálogo com a lista de dispositivos MIDI (conectar/desconectar),
/// atualizada ao vivo por hot-plug enquanto está aberto.
Future<void> showMidiDevicePicker(
  BuildContext context,
  MidiDeviceManager deviceManager,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Dispositivo MIDI'),
      content: SizedBox(
        width: 360,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            deviceManager.devices,
            deviceManager.connected,
            deviceManager.lastError,
          ]),
          builder: (context, _) {
            final devices = deviceManager.devices.value;
            final connected = deviceManager.connected.value;
            final error = deviceManager.lastError.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null) ...[
                  Text(
                    error,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                ],
                if (devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Nenhum dispositivo MIDI encontrado.'),
                  )
                else
                  for (final device in devices)
                    ListTile(
                      leading: Icon(
                        connected?.id == device.id
                            ? Icons.check_circle
                            : Icons.piano,
                        color: connected?.id == device.id
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(device.name),
                      subtitle: Text(device.type.wireValue),
                      onTap: () => connected?.id == device.id
                          ? deviceManager.disconnect()
                          : deviceManager.connect(device),
                    ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
