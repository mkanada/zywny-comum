// `MidiDeviceManager`: conexão automática no plugue (M01).
import 'dart:async';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_midi/midi_device_manager.dart';

/// Só o que o [MidiDeviceManager] usa de [MidiCommand].
class FakeMidiCommand implements MidiCommand {
  List<MidiDevice> list = [];
  final List<String> connects = [];
  final StreamController<MidiSetupChange> setup = StreamController.broadcast();

  /// O Bluetooth: o que a busca mandou fazer, na ordem, e o estado do rádio.
  final List<String> bluetoothCalls = [];
  BluetoothState radio = BluetoothState.poweredOn;

  @override
  void configureBleTransport(MidiBleTransport? transport) =>
      bluetoothCalls.add('configurar');

  @override
  Future<void> startBluetooth() async => bluetoothCalls.add('ligar');

  @override
  Future<void> waitUntilBluetoothIsInitialized() async {}

  @override
  BluetoothState get bluetoothState => radio;

  @override
  Future<void> startScanningForBluetoothDevices() async =>
      bluetoothCalls.add('escanear');

  @override
  void stopScanningForBluetoothDevices() => bluetoothCalls.add('parar');

  @override
  Future<List<MidiDevice>?> get devices async => list;

  @override
  Stream<MidiSetupChange>? get onMidiSetupChanged => setup.stream;

  @override
  Future<void> connectToDevice(
    MidiDevice device, {
    Duration? awaitConnectionTimeout,
  }) async {
    connects.add(device.id);
    device.connected = true;
  }

  @override
  void disconnectDevice(MidiDevice device) => device.connected = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// O transporte BLE de mentira: o [FakeMidiCommand] só o recebe, não o usa.
class FakeBleTransport implements MidiBleTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MidiDevice usb(String id, String name) =>
    MidiDevice(id, name, MidiDeviceType.serial, false);

void main() {
  late FakeMidiCommand midi;
  late MidiDeviceManager manager;

  Future<void> plug(List<MidiDevice> devices) async {
    midi.list = devices;
    midi.setup.add(MidiSetupChange.deviceAppeared);
    await pumpEventQueue();
  }

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    midi = FakeMidiCommand();
    manager = MidiDeviceManager(midi: midi, prefs: SharedPreferencesAsync());
    await pumpEventQueue();
  });

  tearDown(() {
    manager.dispose();
    unawaited(midi.setup.close());
  });

  test('o único teclado com fio conecta sozinho ao ser plugado, mesmo sem '
      'nunca ter sido escolhido', () async {
    expect(manager.connected.value, isNull);
    await plug([usb('3', 'Piano')]);
    expect(manager.connected.value?.id, '3');
  });

  test('replugue com id novo (Android): reconecta pelo nome', () async {
    await plug([usb('3', 'Piano')]);
    await plug([]);
    expect(manager.connected.value, isNull);
    await plug([usb('7', 'Piano'), usb('8', 'Outro')]);
    expect(manager.connected.value?.id, '7');
    expect(midi.connects, ['3', '7']);
  });

  test('dois teclados desconhecidos: não escolhe sozinho', () async {
    await plug([usb('1', 'A'), usb('2', 'B')]);
    expect(manager.connected.value, isNull);
    expect(midi.connects, isEmpty);
  });

  test('desconectar à mão não reconecta enquanto o teclado segue plugado; '
      'replugar volta a conectar', () async {
    final piano = usb('3', 'Piano');
    await plug([piano]);
    manager.disconnect();
    await plug([piano]);
    expect(manager.connected.value, isNull);
    await plug([]);
    await plug([usb('4', 'Piano')]);
    expect(manager.connected.value?.id, '4');
  });

  test(
    'latência e monitor valem para o mesmo teclado depois do replugue',
    () async {
      await plug([usb('3', 'Piano')]);
      await manager.setInputLatencyMs('3', 'app', 42);
      await manager.setMonitorEnabled('3', true);
      await plug([]);
      await plug([usb('7', 'Piano')]);
      expect(await manager.inputLatencyMs('7', 'app'), 42);
      expect(await manager.monitorEnabled('7'), isTrue);
    },
  );

  group('procurar pelo Bluetooth (BLE, Android)', () {
    late MidiDeviceManager ble;

    setUp(() {
      ble = MidiDeviceManager(
        midi: midi,
        prefs: SharedPreferencesAsync(),
        bluetooth: true,
        newBleTransport: () => FakeBleTransport(),
      );
    });

    tearDown(() => ble.dispose());

    test('nada de Bluetooth antes da primeira busca', () async {
      expect(ble.bluetooth, isTrue);
      await pumpEventQueue();
      expect(midi.bluetoothCalls, isEmpty);
    });

    test('instala o BLE, liga, escaneia pela janela e para', () async {
      await ble.searchBluetooth(window: const Duration(milliseconds: 10));
      expect(midi.bluetoothCalls, ['configurar', 'ligar', 'escanear', 'parar']);
      expect(ble.bluetoothNote.value, isNull);
    });

    test('avisa quem já assinou a entrada, só na instalação', () async {
      var installs = 0;
      final sub = ble.transportInstalled.listen((_) => installs++);
      await ble.searchBluetooth(window: const Duration(milliseconds: 10));
      await ble.searchBluetooth(window: const Duration(milliseconds: 10));
      expect(installs, 1);
      await sub.cancel();
    });

    test('a segunda busca não instala o BLE de novo', () async {
      await ble.searchBluetooth(window: const Duration(milliseconds: 10));
      await ble.searchBluetooth(window: const Duration(milliseconds: 10));
      expect(midi.bluetoothCalls.where((c) => c == 'configurar'), hasLength(1));
    });

    test('Bluetooth desligado: avisa e nem escaneia', () async {
      midi.radio = BluetoothState.poweredOff;
      await ble.searchBluetooth(window: const Duration(milliseconds: 10));
      expect(midi.bluetoothCalls, isNot(contains('escanear')));
      expect(ble.bluetoothNote.value, contains('desligado'));
    });

    test('sem permissão: o aviso pede para liberar no app', () async {
      midi.radio = BluetoothState.unauthorized;
      await ble.searchBluetooth(window: const Duration(milliseconds: 10));
      expect(midi.bluetoothCalls, isNot(contains('escanear')));
      expect(ble.bluetoothNote.value, contains('permissão'));
    });

    test('stopBluetoothSearch encerra a janela antes do tempo', () async {
      final search = ble.searchBluetooth(window: const Duration(minutes: 1));
      await pumpEventQueue();
      ble.stopBluetoothSearch();
      await search;
      expect(midi.bluetoothCalls, ['configurar', 'ligar', 'escanear', 'parar']);
    });

    test('sem Bluetooth ligado na configuração, não procura', () async {
      await manager.searchBluetooth(window: const Duration(milliseconds: 10));
      expect(manager.bluetooth, isFalse);
      expect(midi.bluetoothCalls, isEmpty);
    });
  });
}
