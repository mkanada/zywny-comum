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

void main() {
  late _WebFakeMidi midi;
  MidiDeviceManager? manager;

  MidiDeviceManager create({bool supported = true, bool granted = false}) =>
      manager = MidiDeviceManager(
        midi: midi,
        prefs: SharedPreferencesAsync(),
        isWeb: true,
        webSupported: () => supported,
        webGranted: () async => granted,
      );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    midi = _WebFakeMidi();
  });

  tearDown(() {
    manager?.dispose();
    unawaited(midi.setup.close());
  });

  test('sem permissão ainda: não toca no plugin e espera o clique', () async {
    final m = create();
    await pumpEventQueue();
    expect(m.unavailable.value, MidiUnavailable.notAsked);
    expect(midi.deviceReads, 0);
    expect(midi.setupListens, 0);

    midi.list = [MidiDevice('a', 'Piano', MidiDeviceType.serial, false)];
    await m.refresh();
    expect(m.unavailable.value, isNull);
    expect(m.devices.value, hasLength(1));
    expect(m.connected.value?.id, 'a');
    expect(midi.setupListens, 1);
  });

  test('permissão já dada: lista na abertura, sem esperar clique', () async {
    midi.list = [MidiDevice('a', 'Piano', MidiDeviceType.serial, false)];
    final m = create(granted: true);
    await pumpEventQueue();
    expect(m.unavailable.value, isNull);
    expect(m.connected.value?.id, 'a');
  });

  test('navegador sem Web MIDI: avisa e nunca toca no plugin', () async {
    final m = create(supported: false);
    await pumpEventQueue();
    expect(m.unavailable.value, MidiUnavailable.unsupported);
    expect(midi.deviceReads, 0);
  });

  test('UnsupportedError do plugin vira "sem suporte"', () async {
    final m = create();
    await pumpEventQueue();
    midi.failWith = UnsupportedError('Web MIDI API is unavailable');
    await m.refresh();
    expect(m.unavailable.value, MidiUnavailable.unsupported);
  });

  test(
    'acesso recusado vira "negado" e o clique seguinte tenta de novo',
    () async {
      final m = create();
      await pumpEventQueue();
      midi.failWith = StateError('SecurityError');
      await m.refresh();
      expect(m.unavailable.value, MidiUnavailable.denied);
      expect(m.devices.value, isEmpty);

      midi.failWith = null;
      midi.list = [MidiDevice('a', 'Piano', MidiDeviceType.serial, false)];
      await m.refresh();
      expect(m.unavailable.value, isNull);
      expect(m.devices.value, hasLength(1));
    },
  );
}
