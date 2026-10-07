// U17 — o vocabulário das configurações: os rótulos novos e a largura de
// 360 dp (nada estoura, nenhum título quebra em mais de duas linhas).
import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny/midi/midi_device_manager.dart';
import 'package:zywny/settings/app_settings.dart';
import 'package:zywny/app/general_settings_panel.dart';
import 'package:zywny/ui/theme.dart';

class _NoDevicesMidi implements MidiCommand {
  @override
  Future<List<MidiDevice>?> get devices async => const [];

  @override
  Stream<MidiSetupChange>? get onMidiSetupChanged => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('em 360 dp os títulos novos cabem em até duas linhas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings()..output = SoundOutput.midiKeyboard;
    final manager = MidiDeviceManager(
      midi: _NoDevicesMidi(),
      prefs: SharedPreferencesAsync(),
    );
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 3900,
            child: GeneralSettingsPanel(
              settings: settings,
              midiDeviceManager: manager,
              customSoundFont: true,
              onChooseSoundFont: () {},
              onResetSoundFont: () {},
              onClose: () {},
              live: LiveSettingsActions(
                busy: false,
                monitorOn: false,
                onMonitorChanged: (_) {},
                inputLatencyMs: 0,
                onCalibrate: () {},
                onOpenMidiPanel: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    const titles = [
      'Som',
      'Trocar o timbre do teclado',
      'Timbre do piano',
      'Voltar ao timbre padrão',
      'Teclado MIDI',
      'Ouvir o que eu toco pelo celular',
      'Atraso do teclado',
      'Ver as teclas que chegam',
      'Nota certa',
      'Nota esperada',
      'Nota errada',
      'Barra de virada de página',
    ];
    for (final title in titles) {
      final finder = find.text(title);
      expect(finder, findsWidgets, reason: title);
      final text = tester.widget<Text>(finder.last);
      final fontSize = text.style?.fontSize ?? 14;
      expect(
        tester.getSize(finder.last).height,
        lessThanOrEqualTo(fontSize * 1.5 * 2 + 1),
        reason: '"$title" quebra em mais de duas linhas',
      );
    }
    // O seletor de saída ganhou rótulo e os segmentos viraram "Celular" e
    // "Teclado"; as ações à direita têm inicial maiúscula.
    expect(find.text('O som sai por'), findsOneWidget);
    expect(find.text('Celular'), findsOneWidget);
    expect(find.text('Teclado'), findsOneWidget);
    expect(find.text('Trocar'), findsOneWidget);
    expect(find.text('Ajustar'), findsOneWidget);
    expect(find.text('Conectar'), findsOneWidget);
    // Nenhum termo de bancada sobrou.
    for (final old in [
      'Soundfont do sintetizador',
      'Monitor MIDI',
      'Latência do teclado',
      'Painel do monitor MIDI',
      'Largura do halo',
      'Haste de virada',
      'Instrumentos da partitura',
    ]) {
      expect(find.text(old), findsNothing, reason: old);
    }
  });
}
