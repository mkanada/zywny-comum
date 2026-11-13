// `MidiDeviceManager` na Web (W03): a pergunta de permissão só vem de um
// clique, e navegador sem Web MIDI ou com acesso recusado não derruba o app.
import 'dart:async';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_midi/midi_device_manager.dart';

/// Conta quantas vezes o plugin foi tocado (cada toque pede acesso ao
/// navegador) e pode falhar como o plugin Web falha.
class _WebFakeMidi implements MidiCommand {
  Object? failWith;
  int deviceReads = 0;
  int setupListens = 0;
  List<MidiDevice> list = [];
  final StreamController<MidiSetupChange> setup = StreamController.broadcast();

  @override
  Future<List<MidiDevice>?> get devices async {
    deviceReads++;
    final error = failWith;
    if (error != null) throw error;
    return list;
  }

  @override
  Stream<MidiSetupChange>? get onMidiSetupChanged {
    setupListens++;
    return setup.stream;
  }

  @override
  Future<void> connectToDevice(
    MidiDevice device, {
    Duration? awaitConnectionTimeout,
  }) async => device.connected = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

late _WebFakeMidi _midi;

MidiDeviceManager create({bool supported = true, bool granted = false}) =>
    manager = MidiDeviceManager(
      midi: _midi,
      prefs: SharedPreferencesAsync(),
      isWeb: true,
      webSupported: () => supported,
      webGranted: () async => granted,
    );

MidiDeviceManager? manager;

void main() {
  _parte1();
  _parte2();
}

void _parte1() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    _midi = _WebFakeMidi();
  });
  tearDown(() {
    manager?.dispose();
    unawaited(_midi.setup.close());
  });
  test('sem permissão ainda: não toca no plugin e espera o clique', () async {
    final m = create();
    await pumpEventQueue();
    expect(m.unavailable.value, MidiUnavailable.notAsked);
    expect(_midi.deviceReads, 0);
    expect(_midi.setupListens, 0);

    _midi.list = [MidiDevice('a', 'Piano', MidiDeviceType.serial, false)];
    await m.refresh();
    expect(m.unavailable.value, isNull);
    expect(m.devices.value, hasLength(1));
    expect(m.connected.value?.id, 'a');
    expect(_midi.setupListens, 1);
  });
  test('permissão já dada: lista na abertura, sem esperar clique', () async {
    _midi.list = [MidiDevice('a', 'Piano', MidiDeviceType.serial, false)];
    final m = create(granted: true);
    await pumpEventQueue();
    expect(m.unavailable.value, isNull);
    expect(m.connected.value?.id, 'a');
  });
}

void _parte2() {
  test('navegador sem Web MIDI: avisa e nunca toca no plugin', () async {
    final m = create(supported: false);
    await pumpEventQueue();
    expect(m.unavailable.value, MidiUnavailable.unsupported);
    expect(_midi.deviceReads, 0);
  });
  test('UnsupportedError do plugin vira "sem suporte"', () async {
    final m = create();
    await pumpEventQueue();
    _midi.failWith = UnsupportedError('Web MIDI API is unavailable');
    await m.refresh();
    expect(m.unavailable.value, MidiUnavailable.unsupported);
  });
  test(
    'acesso recusado vira "negado" e o clique seguinte tenta de novo',
    () async {
      final m = create();
      await pumpEventQueue();
      _midi.failWith = StateError('SecurityError');
      await m.refresh();
      expect(m.unavailable.value, MidiUnavailable.denied);
      expect(m.devices.value, isEmpty);

      _midi.failWith = null;
      _midi.list = [MidiDevice('a', 'Piano', MidiDeviceType.serial, false)];
      await m.refresh();
      expect(m.unavailable.value, isNull);
      expect(m.devices.value, hasLength(1));
    },
  );
}
