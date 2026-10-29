// A tela do medidor de latência e o item "Latência do som" das configurações.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_comum/app/general_settings_panel.dart';
import 'package:zywny_comum/practice/latency_meter_runner.dart';
import 'package:zywny_comum/practice/latency_meter_screen.dart';
import 'package:zywny_comum/practice/mic_capture.dart';
import 'package:zywny_comum/settings/app_settings.dart';
import 'package:zywny_comum/ui/theme.dart';
import 'package:zywny_midi/midi_device_manager.dart';

import 'support/latency_world.dart';

class _NoDevicesMidi implements MidiCommand {
  @override
  Future<List<MidiDevice>?> get devices async => const [];

  @override
  Stream<MidiSetupChange>? get onMidiSetupChanged => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MidiDevice _piano() => MidiDevice('kb-1', 'Piano', MidiDeviceType.serial, true);

void main() {
  late MidiDeviceManager manager;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    manager = MidiDeviceManager(
      midi: _NoDevicesMidi(),
      prefs: SharedPreferencesAsync(),
    );
  });

  tearDown(() => manager.dispose());

  Future<void> pumpScreen(
    WidgetTester tester,
    LatencyMeterRunner Function(MidiDevice) createRunner,
  ) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LatencyMeterScreen(
          devices: manager,
          device: _piano(),
          createRunner: createRunner,
        ),
      ),
    );
  }

  testWidgets('sem permissão do microfone, explica', (tester) async {
    final world = LatencyWorld();
    await pumpScreen(
      tester,
      (_) => LatencyMeterRunner(
        mic: _DeniedMic(),
        sender: world,
        deviceId: 'kb-1',
      ),
    );
    expect(find.text('Medir'), findsOneWidget);
    await tester.tap(find.text('Medir'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.textContaining('permissão do microfone'), findsOneWidget);
    expect(find.text('Medir de novo'), findsOneWidget);
  });

  testWidgets('mede, mostra o número e guarda a medida', (tester) async {
    final world = LatencyWorld();
    await pumpScreen(
      tester,
      (_) => latencyRunner(world, speaker: LatencyWorldSpeaker(world)),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Medir'));
      for (var i = 0; i < 2000; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await tester.pump();
        if (find.text('Medir de novo').evaluate().isNotEmpty) break;
      }
    });
    expect(find.text('Medir de novo'), findsOneWidget);
    expect(find.textContaining('de atraso entre'), findsOneWidget);
    expect(find.textContaining('descontei'), findsOneWidget);
    final saved = await manager.soundLatency('kb-1');
    expect(saved, isNotNull);
    expect(saved!.ms, closeTo(45, 8));
    expect(saved.corrected, isTrue);
  });

  testWidgets('o item das configurações só aparece com teclado conectado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 2900,
            child: GeneralSettingsPanel(
              settings: AppSettings(),
              midiDeviceManager: manager,
              customSoundFont: false,
              onChooseSoundFont: () {},
              onResetSoundFont: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Latência do som'), findsNothing);

    manager.connected.value = _piano();
    await manager.setSoundLatency('kb-1', 41.6, corrected: true);
    await tester.pumpAndSettle();
    expect(find.text('Latência do som'), findsOneWidget);
    expect(find.text('última medida: 42 ms'), findsOneWidget);
  });
}

class _DeniedMic implements MicCapture {
  @override
  int get sampleRate => 44100;

  @override
  Stream<Int16List> get chunks => const Stream.empty();

  @override
  Future<MicFailure?> start() async => MicFailure.denied;

  @override
  Future<void> stop() async {}
}
