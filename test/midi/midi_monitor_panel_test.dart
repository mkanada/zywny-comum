// O painel do Monitor MIDI (M01) depois da conversão para BLoC: a dica sem
// notas, as notas que chegam na frente e a escuta que para quando o painel sai.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_comum/midi/midi_monitor_panel.dart';
import 'package:zywny_midi/midi_device_manager.dart';
import 'package:zywny_midi/midi_input_service.dart';

/// Só o que o [MidiDeviceManager] usa do [MidiCommand]: sem aparelho.
class _SemTeclado implements MidiCommand {
  @override
  Future<List<MidiDevice>?> get devices async => [];

  @override
  Stream<MidiSetupChange>? get onMidiSetupChanged => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A entrada de notas, sem plataforma: o teste empurra as notas à mão.
class _EntradaFalsa implements MidiInputService {
  final StreamController<PlayedNote> notas =
      StreamController<PlayedNote>.broadcast(sync: true);
  final ValueNotifier<Set<int>> apertadas = ValueNotifier<Set<int>>(const {});

  @override
  Stream<PlayedNote> get notes => notas.stream;

  @override
  Stream<SustainChange> get sustain => const Stream.empty();

  @override
  ValueListenable<Set<int>> get held => apertadas;

  @override
  void dispose() {}
}

void main() {
  late MidiDeviceManager manager;
  late _EntradaFalsa entrada;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    manager = MidiDeviceManager(
      midi: _SemTeclado(),
      prefs: SharedPreferencesAsync(),
    );
    entrada = _EntradaFalsa();
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    await entrada.notas.close();
    manager.dispose();
  });

  Future<void> abrirPainel(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 420,
          child: MidiMonitorPanel(
            deviceManager: manager,
            input: entrada,
            onClose: () {},
          ),
        ),
      ),
    ),
  );

  testWidgets('sem nota, a dica; cada nota que chega entra na frente', (
    tester,
  ) async {
    await abrirPainel(tester);
    expect(find.text('toque uma nota para ver aqui'), findsOneWidget);

    entrada.notas.add(
      const PlayedNote(
        pitch: 60,
        velocity: 90,
        channel: 0,
        on: true,
        atSeconds: 1.5,
      ),
    );
    await tester.pump();

    expect(find.text('toque uma nota para ver aqui'), findsNothing);
    expect(find.textContaining('C4  vel=90  ch=0'), findsOneWidget);
    expect(find.text('1.500s'), findsOneWidget);
  });

  testWidgets('ao sair da tela, a escuta das notas para', (tester) async {
    await abrirPainel(tester);
    expect(entrada.notas.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(entrada.notas.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });
}
