// U08 — ids da mão do app e legenda das cores do treino.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';
import 'package:zywny_audio/performance_track.dart';
import 'package:zywny/practice/app_hand.dart';
import 'package:zywny/practice/hand.dart';
import 'package:zywny/ui/practice_legend.dart';

void main() {
  group('appHandNoteIds', () {
    final track = PerformanceTrack.fromDocument(
      VsbDocument.fromBytes(
        Uint8List.fromList(
          File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
        ),
      ),
    );
    Set<String> idsOfStaff(int staff) => {
      for (final e in track.events)
        if (e.staff == staff) ...[e.id, ...e.tied],
    };

    test('direita: o app toca a pauta 2; esquerda: a pauta 1', () {
      final right = appHandNoteIds(track, Hand.direita);
      final left = appHandNoteIds(track, Hand.esquerda);
      expect(right, isNotEmpty);
      expect(left, isNotEmpty);
      expect(right, idsOfStaff(2));
      expect(left, idsOfStaff(1));
      expect(right.intersection(left), isEmpty);
    });

    test('ambas: o app não toca nenhuma nota', () {
      expect(appHandNoteIds(track, Hand.ambas), isEmpty);
    });
  });

  testWidgets('PracticeLegend mostra os cinco rótulos', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PracticeLegend(
            pending: Colors.blue,
            correct: Colors.green,
            offBeat: Colors.amber,
            wrong: Colors.red,
            missed: Colors.grey,
          ),
        ),
      ),
    );
    for (final label in [
      'esperada',
      'certa',
      'fora do tempo',
      'errada',
      'perdida',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
