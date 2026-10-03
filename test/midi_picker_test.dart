// U15 — o seletor do teclado MIDI, o botão da biblioteca e o rótulo do tipo.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny/midi/midi_device_manager.dart';
import 'package:zywny/midi/midi_device_picker.dart';
import 'package:zywny/midi/midi_labels.dart';

/// Só o que o [MidiDeviceManager] usa de [MidiCommand], contando as leituras
/// da lista de dispositivos.
class _FakeMidiCommand implements MidiCommand {
  List<MidiDevice> list = [];
  int reads = 0;
  final StreamController<MidiSetupChange> setup = StreamController.broadcast();

  @override
  Future<List<MidiDevice>?> get devices async {
    reads++;
    return list;
  }

  @override
  Stream<MidiSetupChange>? get onMidiSetupChanged => setup.stream;

  @override
  Future<void> connectToDevice(
    MidiDevice device, {
    Duration? awaitConnectionTimeout,
  }) async {
    device.connected = true;
  }

  @override
  void disconnectDevice(MidiDevice device) => device.connected = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MidiDevice _usb(String id, String name) =>
    MidiDevice(id, name, MidiDeviceType.serial, false);

void main() {
  late _FakeMidiCommand midi;
  late MidiDeviceManager manager;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    midi = _FakeMidiCommand();
    manager = MidiDeviceManager(midi: midi, prefs: SharedPreferencesAsync());
    await pumpEventQueue();
  });

  tearDown(() => manager.dispose());

  Future<void> openPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMidiDevicePicker(context, manager),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  test('midiDeviceTypeLabel: os seis tipos', () {
    expect(midiDeviceTypeLabel(MidiDeviceType.serial), 'USB');
    expect(midiDeviceTypeLabel(MidiDeviceType.ble), 'Bluetooth');
    expect(midiDeviceTypeLabel(MidiDeviceType.network), 'Rede');
    expect(midiDeviceTypeLabel(MidiDeviceType.virtual), 'Virtual');
    expect(midiDeviceTypeLabel(MidiDeviceType.ownVirtual), 'Virtual');
    expect(midiDeviceTypeLabel(MidiDeviceType.unknown), '');
  });

  test('a orientação só fala de Bluetooth no Android', () {
    expect(midiHelpText(android: true), contains('Bluetooth'));
    expect(midiHelpText(android: false), isNot(contains('Bluetooth')));
    expect(midiHelpText(android: false), contains('cabo USB'));
  });

  testWidgets('vazio: orientação e "Procurar de novo" (que relê a lista)', (
    tester,
  ) async {
    await openPicker(tester);
    expect(find.text('Teclado MIDI'), findsOneWidget); // o título
    expect(find.text('Nenhum teclado encontrado'), findsOneWidget);
    expect(find.textContaining('cabo USB'), findsOneWidget);
    expect(find.text('Procurar de novo'), findsOneWidget);
    final before = midi.reads;
    await tester.tap(find.text('Procurar de novo'));
    await tester.pumpAndSettle();
    expect(midi.reads, greaterThan(before));
  });

  testWidgets('um aparelho desconectado: "Toque para conectar · USB"', (
    tester,
  ) async {
    final device = _usb('1', 'Teclado digital');
    midi.list = [device];
    // O próprio gerente conecta sozinho um único aparelho com fio; para ver
    // o estado "desconectado" o usuário desconecta antes de abrir.
    await manager.refresh();
    await pumpEventQueueForTest(tester);
    manager.disconnect();
    await openPicker(tester);
    expect(find.text('Toque para conectar · USB'), findsOneWidget);
    expect(find.text('Desconectar'), findsNothing);
    expect(find.text('native'), findsNothing);
  });

  testWidgets('conectado: "Conectado · USB" e "Desconectar"', (tester) async {
    midi.list = [_usb('1', 'Teclado digital')];
    await manager.refresh();
    await pumpEventQueueForTest(tester);
    expect(manager.connected.value, isNotNull);
    await openPicker(tester);
    expect(find.text('Conectado · USB'), findsOneWidget);
    expect(find.text('Desconectar'), findsOneWidget);
    expect(find.text('native'), findsNothing);
    await tester.tap(find.text('Desconectar'));
    await tester.pumpAndSettle();
    expect(manager.connected.value, isNull);
    expect(find.text('Toque para conectar · USB'), findsOneWidget);
  });

  testWidgets('o botão da biblioteca é só o ícone e muda ao conectar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MidiStatusPill(deviceManager: manager)),
      ),
    );
    expect(find.text('Conectar'), findsNothing);
    expect(find.byIcon(Icons.piano_off), findsOneWidget);
    expect(find.byTooltip('Conectar teclado MIDI'), findsOneWidget);
    midi.list = [_usb('1', 'Teclado digital')];
    await manager.refresh();
    await tester.pump();
    expect(find.byIcon(Icons.piano), findsOneWidget);
    expect(find.byTooltip('Teclado MIDI: Teclado digital'), findsOneWidget);
  });
}

Future<void> pumpEventQueueForTest(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue(times: 50));
}
