// O painel mostra só o que o app usa. A Trilha de estudo (o N dos trechos, as
// etapas por mão e os andamentos) é dos hinos; o Transpor e a barra de virada
// são das músicas. O aprendizado desliga as três com `showTrail`,
// `showTranspose` e `showPageBar`. A margem do tempo e o brilho ficam nos dois.
import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_midi/midi_device_manager.dart';
import 'package:zywny_comum/app/general_settings_panel.dart';
import 'package:zywny_comum/settings/app_settings.dart';
import 'package:zywny_comum/ui/theme.dart';

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

  /// Monta o painel alto o bastante para o `ListView` construir todas as
  /// linhas (senão o teste não veria as que estão embaixo).
  Future<void> pumpPanel(
    WidgetTester tester, {
    bool showTrail = true,
    bool showTranspose = true,
    bool showPageBar = true,
  }) async {
    tester.view.physicalSize = const Size(360, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
            height: 5900,
            child: GeneralSettingsPanel(
              settings: AppSettings(),
              midiDeviceManager: manager,
              customSoundFont: false,
              onChooseSoundFont: () {},
              onResetSoundFont: () {},
              onClose: () {},
              showTrail: showTrail,
              showTranspose: showTranspose,
              showPageBar: showPageBar,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'por padrão, a trilha aparece com o N, as etapas e os andamentos',
    (tester) async {
      await pumpPanel(tester);
      expect(find.text('Trilha de estudo'), findsOneWidget);
      expect(find.text('Compassos por trecho da trilha'), findsOneWidget);
      expect(find.text('Notas da direita'), findsOneWidget);
      expect(find.text('Andamentos no ritmo'), findsOneWidget);
    },
  );

  testWidgets(
    'sem a trilha, somem a mão, o tamanho e o andamento; a margem fica',
    (tester) async {
      await pumpPanel(tester, showTrail: false);
      expect(find.text('Trilha de estudo'), findsNothing);
      expect(find.text('Compassos por trecho da trilha'), findsNothing);
      expect(find.text('Notas da direita'), findsNothing);
      expect(find.text('Notas da esquerda'), findsNothing);
      expect(find.text('Andamentos no ritmo'), findsNothing);
      expect(find.text('Ritmo'), findsOneWidget);
      expect(
        find.text('Margem do tempo (no andamento original)'),
        findsOneWidget,
      );
      // Logo depois da trilha: prova que a lista foi construída até aqui.
      expect(find.text('Cores'), findsOneWidget);
    },
  );

  testWidgets(
    'sem o transpor e a barra de virada; o brilho e as outras cores ficam',
    (tester) async {
      await pumpPanel(tester, showTranspose: false, showPageBar: false);
      expect(find.text('Transpor'), findsNothing);
      expect(find.text('Abrir as músicas já sem acidentes'), findsNothing);
      expect(find.text('Barra de virada de página'), findsNothing);
      expect(find.text('Brilho em volta da nota'), findsOneWidget);
      expect(find.text('Nota certa'), findsOneWidget);
    },
  );
}
