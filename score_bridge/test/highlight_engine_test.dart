// `HighlightEngine` (A02a): tempo simulado, sem `Ticker` nem widget.
import 'dart:io';

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

const _base = Color(0xFF000000);
const _red = Color(0xFFD32F2F);

Duration ms(int v) => Duration(milliseconds: v);

/// Diferença máxima por canal, em passos de 8 bits.
double _maxChannelDiff(Color a, Color b) {
  double d(double x, double y) => ((x - y) * 255).abs();
  return [
    d(a.a, b.a),
    d(a.r, b.r),
    d(a.g, b.g),
    d(a.b, b.b),
  ].reduce((m, v) => v > m ? v : m);
}

/// A resposta "à mão": a cor esperada de uma nota de `start` a `t`, escrita
/// direto das definições das fases (sem usar o motor).
Color _byHand({
  required int t,
  required int start,
  required int attack,
  required int hold,
  required int release,
  required Color from,
  required Color to,
  Curve curve = Curves.linear,
}) {
  final e = t - start;
  if (e < attack) {
    return Color.lerp(from, to, curve.transform(e / attack))!;
  }
  if (e < attack + hold) {
    return to;
  }
  final r = e - attack - hold;
  if (r >= release) {
    return from;
  }
  return Color.lerp(to, from, curve.transform(r / release))!;
}

void main() {
  test('50 notas em 5 instantes batem com o cálculo à mão (1/255)', () {
    final engine = HighlightEngine();
    final specs = <String, List<int>>{};
    for (var i = 0; i < 50; i++) {
      final start = (i * 37) % 400;
      final attack = 20 + (i % 7) * 30;
      final hold = (i % 5) * 50;
      final release = 100 + (i % 9) * 40;
      specs['n$i'] = [start, attack, hold, release];
      final target = Color.fromARGB(255, (i * 5) % 256, 255 - i * 4, i * 3);
      engine.start(
        'n$i',
        HighlightSpec(
          color: target,
          baseColor: i.isEven ? _base : const Color(0xFF0000FF),
          attack: ms(attack),
          hold: ms(hold),
          release: ms(release),
          curve: Curves.linear,
        ),
        ms(start),
      );
    }
    final targets = <String, Color>{
      for (var i = 0; i < 50; i++)
        'n$i': Color.fromARGB(255, (i * 5) % 256, 255 - i * 4, i * 3),
    };
    for (final t in [450, 520, 640, 800, 1100]) {
      final colors = Map.of(engine.colorsAt(ms(t)));
      for (var i = 0; i < 50; i++) {
        final s = specs['n$i']!;
        // `start` de cada nota é o argumento de `start()`, mas todas foram
        // iniciadas com `now = start`, e o motor é consultado depois.
        final base = i.isEven ? _base : const Color(0xFF0000FF);
        final expected = _byHand(
          t: t,
          start: s[0],
          attack: s[1],
          hold: s[2],
          release: s[3],
          from: base,
          to: targets['n$i']!,
        );
        final actual = colors['n$i'];
        if (actual == null) {
          // Terminou antes de t: já saiu do mapa numa chamada anterior.
          expect(t - s[0], greaterThanOrEqualTo(s[1] + s[2] + s[3]));
          continue;
        }
        expect(
          _maxChannelDiff(actual, expected),
          lessThanOrEqualTo(1.0),
          reason: 'n$i em t=$t: $actual vs $expected',
        );
      }
    }
  });

  test('reiniciar uma nota não muda a cor de nenhuma outra', () {
    HighlightEngine build() {
      final e = HighlightEngine();
      for (var i = 0; i < 20; i++) {
        e.start(
          'n$i',
          HighlightSpec(
            color: _red,
            baseColor: _base,
            attack: ms(100),
            hold: ms(100),
            release: ms(300),
          ),
          ms(i * 10),
        );
      }
      return e;
    }

    final a = build();
    final b = build();
    b.start(
      'n7',
      const HighlightSpec(color: Color(0xFF00FF00), baseColor: _base),
      ms(250),
    );
    final ca = Map.of(a.colorsAt(ms(300)));
    final cb = Map.of(b.colorsAt(ms(300)));
    for (var i = 0; i < 20; i++) {
      if (i == 7) {
        continue;
      }
      expect(cb['n$i'], ca['n$i'], reason: 'n$i');
    }
    expect(cb['n7'], isNot(ca['n7']));
  });

  test('ao fim do release a cor é exatamente a base e o id sai do mapa', () {
    final engine = HighlightEngine();
    const base = Color(0xFF123456);
    engine.start(
      'a',
      const HighlightSpec(
        color: _red,
        baseColor: base,
        attack: Duration(milliseconds: 50),
        release: Duration(milliseconds: 100),
      ),
      Duration.zero,
    );
    expect(engine.isIdle, isFalse);
    expect(engine.colorsAt(ms(120)).containsKey('a'), isTrue);
    final end = engine.colorsAt(ms(150));
    expect(end['a'], base); // igualdade exata, não tolerância
    expect(engine.isActive('a'), isFalse);
    expect(engine.colorsAt(ms(200)).containsKey('a'), isFalse);
  });

  test('ociosidade: isIdle depois da última nota', () {
    final engine = HighlightEngine();
    expect(engine.isIdle, isTrue);
    for (var i = 0; i < 3; i++) {
      engine.start(
        'n$i',
        HighlightSpec(
          color: _red,
          baseColor: _base,
          release: ms(100 * (i + 1)),
        ),
        Duration.zero,
      );
    }
    engine.colorsAt(ms(150));
    expect(engine.isIdle, isFalse);
    engine.colorsAt(ms(250));
    expect(engine.isIdle, isFalse);
    engine.colorsAt(ms(300));
    expect(engine.isIdle, isTrue);
  });

  test('a curva é aplicada ao parâmetro t, não ao resultado', () {
    final engine = HighlightEngine();
    engine.start(
      'a',
      const HighlightSpec(
        color: Color(0xFFFFFFFF),
        baseColor: Color(0xFF000000),
        attack: Duration(milliseconds: 200),
        hold: Duration(milliseconds: 1000),
        curve: Curves.easeOut,
      ),
      Duration.zero,
    );
    final actual = engine.colorsAt(ms(100))['a']!;
    final k = Curves.easeOut.transform(0.5);
    expect(k, isNot(0.5)); // a curva realmente deforma
    final expected = Color.lerp(
      const Color(0xFF000000),
      const Color(0xFFFFFFFF),
      k,
    )!;
    expect(_maxChannelDiff(actual, expected), lessThanOrEqualTo(1.0));
    // E não é o linear.
    expect(
      _maxChannelDiff(
        actual,
        Color.lerp(const Color(0xFF000000), const Color(0xFFFFFFFF), 0.5)!,
      ),
      greaterThan(10),
    );
    // No release a curva também vale (cor -> base).
    final e2 = HighlightEngine();
    e2.start(
      'a',
      const HighlightSpec(
        color: Color(0xFFFFFFFF),
        baseColor: Color(0xFF000000),
        release: Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
      Duration.zero,
    );
    final r = e2.colorsAt(ms(100))['a']!;
    expect(
      _maxChannelDiff(
        r,
        Color.lerp(const Color(0xFFFFFFFF), const Color(0xFF000000), k)!,
      ),
      lessThanOrEqualTo(1.0),
    );
  });

  test('durações zero são válidas (attack: 0 é destaque instantâneo)', () {
    final engine = HighlightEngine();
    engine.start(
      'a',
      const HighlightSpec(
        color: _red,
        baseColor: _base,
        release: Duration(milliseconds: 100),
      ),
      ms(10),
    );
    expect(engine.colorsAt(ms(10))['a'], _red);
    // release zero, attack zero: termina no mesmo instante, na base.
    engine.start(
      'b',
      const HighlightSpec(
        color: _red,
        baseColor: _base,
        release: Duration.zero,
      ),
      ms(10),
    );
    expect(engine.colorsAt(ms(10))['b'], _base);
    expect(engine.isActive('b'), isFalse);
  });

  test('stop antecipa o release sem salto de cor', () {
    final engine = HighlightEngine();
    engine.start(
      'a',
      const HighlightSpec(
        color: Color(0xFFFFFFFF),
        baseColor: Color(0xFF000000),
        attack: Duration(milliseconds: 100),
        hold: Duration(seconds: 10),
        curve: Curves.linear,
      ),
      Duration.zero,
    );
    final before = engine.colorsAt(ms(50))['a']!; // 50% do attack
    engine.stop('a', ms(50), release: ms(100), curve: Curves.linear);
    final at = engine.colorsAt(ms(50))['a']!;
    expect(at, before);
    // Metade do release, partindo do cinza: 25% do branco.
    final half = engine.colorsAt(ms(100))['a']!;
    expect(
      _maxChannelDiff(half, Color.lerp(before, const Color(0xFF000000), 0.5)!),
      lessThanOrEqualTo(1.0),
    );
    engine.colorsAt(ms(150));
    expect(engine.isIdle, isTrue);
  });

  test('colorsAt não aloca estrutura por frame (1 000 chamadas, 64 notas)', () {
    final engine = HighlightEngine();
    for (var i = 0; i < 64; i++) {
      engine.start(
        'n$i',
        const HighlightSpec(
          color: _red,
          baseColor: _base,
          attack: Duration(seconds: 100),
          hold: Duration(seconds: 100),
          release: Duration(seconds: 100),
        ),
        Duration.zero,
      );
    }
    final first = engine.colorsAt(ms(1));
    // Aquece (JIT, tabelas).
    for (var i = 0; i < 3000; i++) {
      engine.colorsAt(ms(i));
    }
    final rssBefore = ProcessInfo.currentRss;
    for (var i = 0; i < 1000; i++) {
      final map = engine.colorsAt(ms(1000 + i));
      // Mesmo mapa, sempre: nenhuma lista/mapa novo por chamada.
      expect(identical(map, first), isTrue);
    }
    final growth = ProcessInfo.currentRss - rssBefore;
    // Dezenas de milhares de `Color` de vida curta passam pelo GC jovem;
    // o que não pode existir é crescimento retido.
    expect(growth, lessThan(4 * 1024 * 1024), reason: 'RSS +$growth bytes');
    expect(engine.activeCount, 64);
  });
}
