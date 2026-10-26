import 'dart:math' show Random;

import 'chord_degree.dart';

/// Como as fundamentais andam (EX00, seção Ciclos).
enum RootSequence { random, cycle5, cycle4, chromatic, wholeTone, diatonic }

/// [count] fundamentais (classes de altura) a partir de [from] (Dó = 0).
///
/// * `random`: sorteadas, sem repetir a nota em seguida ([rng]).
/// * `cycle5`: de quinta em quinta descendo (C F B♭ E♭ A♭ D♭ G♭ B E A D G).
/// * `cycle4`: de quarta em quarta descendo, ou quinta subindo.
/// * `chromatic`: descendo por semitom.
/// * `wholeTone`: as 6 da série de tons descendo e depois as outras 6, um
///   semitom acima; repete a cada 12.
/// * `diatonic`: os sete graus do tom [key], subindo e descendo.
///
/// Os ciclos repetem a cada 12 fundamentais quando [count] passa de 12.
List<int> rootSequence(
  RootSequence seq, {
  int from = 0,
  required int count,
  KeySpec? key,
  Random? rng,
}) {
  final random = rng ?? Random();
  return switch (seq) {
    RootSequence.random => _random(from, count, random),
    RootSequence.cycle5 => [
      for (var i = 0; i < count; i++) _mod12(from + 5 * i),
    ],
    RootSequence.cycle4 => [
      for (var i = 0; i < count; i++) _mod12(from + 7 * i),
    ],
    RootSequence.chromatic => [
      for (var i = 0; i < count; i++) _mod12(from - i),
    ],
    RootSequence.wholeTone => [
      for (var i = 0; i < count; i++) _mod12(from + _wholeTone(i % 12)),
    ],
    RootSequence.diatonic => _diatonic(key, count),
  };
}

/// As 12 posições da série de tons: 0, -2, … -10 (as seis da série), e
/// depois a série de novo um semitom acima (1, -1, … -9).
int _wholeTone(int i) => i < 6 ? -2 * i : 1 - 2 * (i - 6);

List<int> _random(int from, int count, Random random) {
  final result = <int>[from];
  while (result.length < count) {
    final next = random.nextInt(12);
    if (next != result.last) result.add(next);
  }
  return result.sublist(0, count);
}

List<int> _diatonic(KeySpec? key, int count) {
  if (key == null) {
    throw ArgumentError('`diatonic` pede o tom (key:).');
  }
  final steps = key.minor ? _minorSteps : _majorSteps;
  return [
    for (var i = 0; i < count; i++) _mod12(key.tonic + steps[_updown(i % 12)]),
  ];
}

/// Os índices dos sete graus na ida e na volta: 0 1 2 3 4 5 6 5 4 3 2 1.
int _updown(int i) => i < 7 ? i : 12 - i;

int _mod12(int x) => ((x % 12) + 12) % 12;

const _majorSteps = [0, 2, 4, 5, 7, 9, 11];
const _minorSteps = [0, 2, 3, 5, 7, 8, 10];
