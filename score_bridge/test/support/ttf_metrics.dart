// Leitura mínima de métricas de avanço de uma TTF (R04a, só para teste).
//
// Soma os avanços horizontais (`hmtx`) dos codepoints de uma string,
// escalados por `size / unitsPerEm` (`head`). Serve de verdade independente
// para o teste antifallback: se o `TextPainter` estiver usando outra fonte
// (fallback silencioso), a largura não bate.
//
// Cobre `cmap` formato 4 (BMP) e 12 (Unicode pleno); a string do critério
// ("Allegro molto agitato.") é ASCII, então o formato 4 basta, mas o 12
// existe nas Liberation e é preferido quando presente.
library;

import 'dart:typed_data';

/// Métricas de avanço de uma TTF carregada em memória.
class TtfAdvances {
  TtfAdvances._(
    this.unitsPerEm,
    this.ascentUnits,
    this.descentUnits,
    this.gapUnits,
    this._glyphFor,
    this._advances,
  );

  final int unitsPerEm;

  /// Métricas verticais do `hhea` em unidades da fonte (`descentUnits` com
  /// sinal, negativo para baixo da linha de base).
  final int ascentUnits;
  final int descentUnits;
  final int gapUnits;
  final int Function(int codepoint) _glyphFor;
  final List<int> _advances;

  int get _lastAdvance => _advances.last;

  factory TtfAdvances.parse(ByteData data) {
    int u16(int offset) => data.getUint16(offset, Endian.big);
    int u32(int offset) => data.getUint32(offset, Endian.big);

    final numTables = u16(4);
    final tables = <String, int>{};
    for (var k = 0; k < numTables; k++) {
      final base = 12 + k * 16;
      final tag = String.fromCharCodes([
        data.getUint8(base),
        data.getUint8(base + 1),
        data.getUint8(base + 2),
        data.getUint8(base + 3),
      ]);
      tables[tag] = u32(base + 8);
    }

    int table(String tag) {
      final offset = tables[tag];
      if (offset == null) {
        throw StateError('TTF sem tabela $tag');
      }
      return offset;
    }

    final unitsPerEm = u16(table('head') + 18);
    final hhea = table('hhea');
    // Verticais do `hhea` são int16 com sinal.
    final ascent = data.getInt16(hhea + 4, Endian.big);
    final descent = data.getInt16(hhea + 6, Endian.big);
    final gap = data.getInt16(hhea + 8, Endian.big);
    final numHMetrics = u16(hhea + 34);
    final hmtx = table('hmtx');
    final advances = List<int>.generate(numHMetrics, (k) => u16(hmtx + k * 4));

    final glyphFor = _parseCmap(data, table('cmap'));
    return TtfAdvances._(unitsPerEm, ascent, descent, gap, glyphFor, advances);
  }

  /// Distância topo→linha de base alfabética a [size] px, com `height: 1.0`.
  ///
  /// Sem `height`, o Skia empilha `ascent + descent + gap` e reparte meio
  /// `gap` acima do ascendente (`dy = asc + gap/2`, medido); com
  /// `height: 1.0` o Flutter reescala essas métricas naturais para 1 em, de
  /// modo que `dy = (asc + gap/2) / (asc - desc + gap) × size`. Para a
  /// Liberation Serif Regular a 405: 321,33 px — o `computeDistanceToActual
  /// Baseline` do pintor devolve o mesmo número (critério 2 de R04b).
  double ascentOf(double size) =>
      (ascentUnits + gapUnits / 2.0) /
      (ascentUnits - descentUnits + gapUnits) *
      size;

  static int Function(int) _parseCmap(ByteData data, int cmap) {
    int u16(int offset) => data.getUint16(offset, Endian.big);
    int u32(int offset) => data.getUint32(offset, Endian.big);

    final numTables = u16(cmap + 2);
    int? format4;
    int? format12;
    for (var k = 0; k < numTables; k++) {
      final base = cmap + 4 + k * 8;
      final platform = u16(base);
      final encoding = u16(base + 2);
      final offset = cmap + u32(base + 4);
      final format = u16(offset);
      if (format == 12) {
        format12 ??= offset;
      } else if (format == 4) {
        // Prefere Windows BMP (3,1); aceita qualquer outro como reserva.
        if (platform == 3 && encoding == 1) {
          format4 = offset;
          break;
        }
        format4 ??= offset;
      }
    }
    if (format12 != null) {
      return _cmap12(data, format12);
    }
    if (format4 != null) {
      return _cmap4(data, format4);
    }
    throw StateError('TTF sem cmap formato 4 nem 12');
  }

  static int Function(int) _cmap12(ByteData data, int offset) {
    int u32(int off) => data.getUint32(off, Endian.big);
    final numGroups = u32(offset + 12);
    final starts = <int>[];
    final ends = <int>[];
    final glyphs = <int>[];
    for (var k = 0; k < numGroups; k++) {
      final base = offset + 16 + k * 12;
      starts.add(u32(base));
      ends.add(u32(base + 4));
      glyphs.add(u32(base + 8));
    }
    return (codepoint) {
      for (var k = 0; k < numGroups; k++) {
        if (codepoint >= starts[k] && codepoint <= ends[k]) {
          return glyphs[k] + (codepoint - starts[k]);
        }
      }
      return 0;
    };
  }

  static int Function(int) _cmap4(ByteData data, int offset) {
    int u16(int off) => data.getUint16(off, Endian.big);
    final segCount = u16(offset + 6) ~/ 2;
    final endBase = offset + 14;
    final startBase = endBase + segCount * 2 + 2;
    final deltaBase = startBase + segCount * 2;
    final rangeBase = deltaBase + segCount * 2;
    final ends = List<int>.generate(segCount, (k) => u16(endBase + k * 2));
    final starts = List<int>.generate(segCount, (k) => u16(startBase + k * 2));
    return (codepoint) {
      for (var k = 0; k < segCount; k++) {
        if (codepoint > ends[k] || codepoint < starts[k]) {
          continue;
        }
        final rangeOffset = u16(rangeBase + k * 2);
        if (rangeOffset == 0) {
          return (codepoint + u16(deltaBase + k * 2)) & 0xFFFF;
        }
        final addr =
            rangeBase + k * 2 + rangeOffset + 2 * (codepoint - starts[k]);
        final glyph = u16(addr);
        if (glyph == 0) {
          return 0;
        }
        return (glyph + u16(deltaBase + k * 2)) & 0xFFFF;
      }
      return 0;
    };
  }

  /// Largura da [string] a [size] px: soma dos avanços × `size/unitsPerEm`.
  double widthOf(String string, double size) {
    var total = 0;
    for (final codepoint in string.runes) {
      final glyph = _glyphFor(codepoint);
      total += glyph < _advances.length ? _advances[glyph] : _lastAdvance;
    }
    return total * size / unitsPerEm;
  }
}
