// U11 — seletor único de modos e a gaveta de opções.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/practice/hand.dart';
import 'package:zywny/practice/practice_controller.dart' show PracticeMode;
import 'package:zywny/practice/study_mode.dart';
import 'package:zywny/ui/phone_chrome.dart';

Widget _drawer({
  StudyMode mode = StudyMode.wait,
  ValueChanged<StudyMode>? onModeChanged,
  bool trailMode = false,
  List<Widget> top = const [],
}) => MaterialApp(
  home: Scaffold(
    body: Stack(
      children: [
        PhoneOptionsDrawer(
          mode: mode,
          onModeChanged: onModeChanged,
          trailMode: trailMode,
          hand: Hand.direita,
          onHandChanged: (_) {},
          tempoPercent: 80,
          onTempoChanged: (_) {},
          onClose: () {},
          top: top,
          children: const [PhoneSectionLabel('ESTE HINO')],
        ),
      ],
    ),
  ),
);

void main() {
  group('StudyMode ↔ (treino armado, modo de treino)', () {
    test('as combinações, de ida e volta', () {
      expect(
        StudyMode.of(training: false, mode: PracticeMode.wait),
        StudyMode.listen,
      );
      // Sem treino armado o modo de treino guardado não importa.
      expect(
        StudyMode.of(training: false, mode: PracticeMode.realtime),
        StudyMode.listen,
      );
      expect(
        StudyMode.of(training: true, mode: PracticeMode.wait),
        StudyMode.wait,
      );
      expect(
        StudyMode.of(training: true, mode: PracticeMode.realtime),
        StudyMode.realtime,
      );
      for (final m in StudyMode.values) {
        final practice = m.practiceMode;
        expect(m.isTraining, practice != null);
        if (practice != null) {
          expect(StudyMode.of(training: true, mode: practice), m);
        }
      }
    });
  });

  group('PhoneOptionsDrawer', () {
    for (final mode in StudyMode.values) {
      testWidgets('${mode.label}: explica o modo e não há interruptores', (
        tester,
      ) async {
        await tester.pumpWidget(_drawer(mode: mode, onModeChanged: (_) {}));
        expect(find.text(mode.explanation), findsOneWidget);
        for (final other in StudyMode.values.where((m) => m != mode)) {
          expect(find.text(other.explanation), findsNothing);
        }
        expect(find.text('Tempo real (a música não espera)'), findsNothing);
        expect(find.byType(Switch), findsNothing);
        for (final m in StudyMode.values) {
          expect(find.text(m.label), findsOneWidget);
        }
      });
    }

    testWidgets('escolher um segmento chama o retorno com o modo', (
      tester,
    ) async {
      StudyMode? chosen;
      await tester.pumpWidget(_drawer(onModeChanged: (m) => chosen = m));
      await tester.tap(find.text('Tempo real'));
      expect(chosen, StudyMode.realtime);
      await tester.tap(find.text('Ouvir'));
      expect(chosen, StudyMode.listen);
    });

    testWidgets('com o retorno nulo (treino rodando) o seletor não responde', (
      tester,
    ) async {
      await tester.pumpWidget(_drawer());
      // Sem retorno: nenhum toque no seletor tem efeito nem lança.
      await tester.tap(find.text('Tempo real'), warnIfMissed: false);
      expect(tester.takeException(), isNull);
    });

    testWidgets('na trilha: sem MODO, MÃO e ANDAMENTO; a trilha à vista em '
        '640×360', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _drawer(
          trailMode: true,
          top: [
            const PhoneSectionLabel('TRILHA'),
            PhoneActionRow(
              icon: Icons.school_outlined,
              label: 'Treino livre',
              onTap: null,
            ),
          ],
        ),
      );
      expect(find.text('MODO'), findsNothing);
      expect(find.text('MÃO'), findsNothing);
      expect(find.text('ANDAMENTO'), findsNothing);
      expect(find.text('TRILHA'), findsOneWidget);
      final row = tester.getRect(find.text('Treino livre'));
      expect(row.bottom, lessThan(360));
      expect(row.top, greaterThan(0));
    });

    testWidgets('no treino livre "Voltar à trilha" fica antes do modo', (
      tester,
    ) async {
      await tester.pumpWidget(
        _drawer(
          onModeChanged: (_) {},
          top: [
            const PhoneSectionLabel('TRILHA'),
            PhoneActionRow(
              icon: Icons.route,
              label: 'Voltar à trilha',
              onTap: null,
            ),
          ],
        ),
      );
      expect(
        tester.getRect(find.text('Voltar à trilha')).top,
        lessThan(tester.getRect(find.text('MODO')).top),
      );
    });
  });
}
