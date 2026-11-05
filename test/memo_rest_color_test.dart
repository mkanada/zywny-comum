// `kMemoRestColor` (L03): a cor da pausa substituta tem de se distinguir das
// outras cores do treino, que ocupam a mesma partitura.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart' show kDefaultGhostColor;
import 'package:zywny_comum/practice/practice_colors.dart';

/// Distância euclidiana entre duas cores, em RGB de 0 a 255.
double _distance(Color a, Color b) {
  double d(double x, double y) => (x - y) * 255;
  return math.sqrt(
    math.pow(d(a.r, b.r), 2) + math.pow(d(a.g, b.g), 2) + math.pow(d(a.b, b.b), 2),
  );
}

void main() {
  test('kMemoRestColor é opaca e distinta das cores do treino', () {
    expect(kMemoRestColor.a, 1.0);
    final others = {
      'certa (verde)': kPracticeCorrectColor,
      'pendente (azul)': kPracticePendingColor,
      'errada (vermelho)': kPracticeWrongColor,
      'fora do tempo (âmbar)': kPracticeOffBeatColor,
      'perdida (cinza)': kPracticeMissedColor,
      'mão do app (cinza claro)': kPracticeAppHandColor,
      'fantasma (laranja)': kDefaultGhostColor,
      'compasso reprovado (violeta)': kPracticeMeterMarkColor,
    };
    others.forEach((name, color) {
      expect(
        _distance(kMemoRestColor, color),
        greaterThan(40),
        reason: 'confunde com $name',
      );
    });
  });
}
