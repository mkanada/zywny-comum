// O "Reportar um bug" das configurações: fecha o painel (a captura é da tela
// onde o erro aconteceu) e abre o relatório; sem o escopo, a linha não existe.
import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_comum/app/general_settings_panel.dart';
import 'package:zywny_comum/diag/bug_report_scope.dart';
import 'package:zywny_comum/settings/app_settings.dart';
import 'package:zywny_comum/ui/theme.dart';
import 'package:zywny_midi/midi_device_manager.dart';

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

  Future<void> pumpPanel(WidgetTester tester, {VoidCallback? onClose}) async {
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
        builder: onClose == null
            ? null
            : (context, child) =>
                  BugReportScope(appName: 'teste', child: child!),
        home: Scaffold(
          body: GeneralSettingsPanel(
            settings: AppSettings(),
            midiDeviceManager: manager,
            customSoundFont: false,
            onChooseSoundFont: () {},
            onResetSoundFont: () {},
            onClose: onClose ?? () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('sem o escopo a linha não aparece', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Reportar um bug'), findsNothing);
  });

  testWidgets('a linha fecha o painel e abre o relatório', (tester) async {
    var closed = 0;
    await pumpPanel(tester, onClose: () => closed++);

    await tester.tap(find.text('Reportar um bug'));
    await tester.pump();
    expect(closed, 1);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Gerar relatório'), findsOneWidget);
  });
}
