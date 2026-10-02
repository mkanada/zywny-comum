import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

import '../ui/theme.dart';
import 'midi_device_manager.dart';
import 'midi_labels.dart';

/// Ícone do teclado MIDI para a AppBar (M01): mostra se algo está
/// conectado e abre [showMidiDevicePicker] ao tocar.
class MidiDevicePickerButton extends StatelessWidget {
  const MidiDevicePickerButton({
    super.key,
    required this.deviceManager,
    this.onCalibrate,
  });

  final MidiDeviceManager deviceManager;

  /// Abre a tela de calibração de latência (T04); `null` esconde o botão.
  final VoidCallback? onCalibrate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: deviceManager.connected,
      builder: (context, _) {
        final device = deviceManager.connected.value;
        return IconButton(
          tooltip: device == null
              ? 'Conectar teclado MIDI'
              : 'Teclado MIDI: ${device.name}',
          onPressed: () => showMidiDevicePicker(
            context,
            deviceManager,
            onCalibrate: onCalibrate,
          ),
          icon: Icon(device == null ? Icons.piano_outlined : Icons.piano),
        );
      },
    );
  }
}

/// O estado do teclado em palavras e ícone (U15): "Conectar" com o teclado
/// riscado, "Teclado ✓" conectado — não um ponto colorido. Toque abre
/// [showMidiDevicePicker].
class MidiStatusPill extends StatelessWidget {
  const MidiStatusPill({super.key, required this.deviceManager});

  final MidiDeviceManager deviceManager;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: deviceManager.connected,
      builder: (context, _) {
        final device = deviceManager.connected.value;
        final connected = device != null;
        return Tooltip(
          message: connected
              ? 'Teclado MIDI: ${device.name}'
              : 'Conectar teclado MIDI',
          child: Material(
            color: kChipBg,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () =>
                  unawaited(showMidiDevicePicker(context, deviceManager)),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      connected ? Icons.piano : Icons.piano_off,
                      size: 20,
                      color: connected ? kGoodColor : kInk,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      connected ? 'Teclado ✓' : 'Conectar',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: connected ? kGoodColor : kInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A orientação de quem ainda não tem teclado ligado. Só o Android avisa do
/// Bluetooth: é onde "ainda não funciona" é verdade hoje (M01: o plugin BLE
/// está pendente).
String midiHelpText({required bool android}) =>
    'Ligue o teclado ao celular com um cabo USB (pode ser preciso um '
    'adaptador). Ele conecta sozinho.'
    '${android ? '\nTeclados por Bluetooth ainda não funcionam.' : ''}';

/// Diálogo do teclado MIDI: o que está conectado, a lista de aparelhos
/// (atualizada ao vivo por hot-plug enquanto está aberto) e, sem nenhum, a
/// orientação para ligar um e o botão de procurar de novo.
Future<void> showMidiDevicePicker(
  BuildContext context,
  MidiDeviceManager deviceManager, {
  VoidCallback? onCalibrate,
}) {
  final searching = ValueNotifier<bool>(false);
  Future<void> search() async {
    searching.value = true;
    try {
      await deviceManager.refresh();
    } finally {
      searching.value = false;
    }
  }

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Teclado MIDI'),
      content: SizedBox(
        width: 360,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            deviceManager.devices,
            deviceManager.connected,
            deviceManager.lastError,
            searching,
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
                    'Não deu para conectar. $error',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (devices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.piano_off,
                          size: 36,
                          color: kInkCaption,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Nenhum teclado encontrado',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          midiHelpText(
                            android:
                                defaultTargetPlatform == TargetPlatform.android,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: searching.value ? null : search,
                          child: searching.value
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Procurar de novo'),
                        ),
                      ],
                    ),
                  )
                else
                  for (final device in devices)
                    _deviceTile(
                      device,
                      isConnected: connected?.id == device.id,
                      deviceManager: deviceManager,
                      context: context,
                    ),
              ],
            );
          },
        ),
      ),
      actions: [
        if (onCalibrate != null)
          TextButton(
            onPressed: deviceManager.connected.value == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    onCalibrate();
                  },
            child: const Text('Ajustar o atraso'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  ).whenComplete(searching.dispose);
}

Widget _deviceTile(
  MidiDevice device, {
  required bool isConnected,
  required MidiDeviceManager deviceManager,
  required BuildContext context,
}) {
  final type = midiDeviceTypeLabel(device.type);
  final state = isConnected ? 'Conectado' : 'Toque para conectar';
  return ListTile(
    leading: Icon(
      isConnected ? Icons.check_circle : Icons.piano,
      color: isConnected ? Theme.of(context).colorScheme.primary : null,
    ),
    title: Text(device.name),
    subtitle: Text(type.isEmpty ? state : '$state · $type'),
    // Conectado: a ação é o botão "Desconectar", não o toque na linha.
    trailing: isConnected
        ? TextButton(
            onPressed: deviceManager.disconnect,
            child: const Text('Desconectar'),
          )
        : null,
    onTap: isConnected ? null : () => deviceManager.connect(device),
  );
}
