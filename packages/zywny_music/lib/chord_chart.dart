// EX09 — a grade de acordes (`ChordChart`): o modelo da marca `zywny-chart` e,
// depois, do `play-chart`. Dart puro.
//
// O texto da grade é lido compasso a compasso: `|` separa, `|:` e `:|` (com
// `x3`) repetem, `[1` … `]` e `[2` … são as casas, e `A:` no começo da linha
// abre uma seção. Um acorde ocupa uma fatia do compasso, e o número de fatias
// divide os tempos. `expand()` põe os compassos na ordem em que se tocam e
// `slots()` põe os acordes no tempo.

import 'package:meta/meta.dart';

import 'chord.dart';
import 'chord_degree.dart';
import 'progressions.dart';

/// Um acorde escrito na grade: a cifra e o grau no tom (o que `degrees: true`
/// mostra). No `N.C.`, a cifra é `null` e o grau é `N.C.`.
@immutable
class ChartChord {
  const ChartChord({required this.chord, required this.degree});

  final ChordSymbol? chord;
  final String degree;

  @override
  bool operator ==(Object other) =>
      other is ChartChord && other.chord == chord && other.degree == degree;

  @override
  int get hashCode => Object.hash(chord, degree);

  @override
  String toString() => degree;
}

/// Um compasso escrito, com as marcas de repetição e de casa.
@immutable
class ChartBar {
  const ChartBar({
    required this.chords,
    this.repeatStart = false,
    this.repeatTimes,
    this.ending,
  });

  /// Os acordes do compasso, um por fatia, na ordem em que soam.
  final List<ChartChord> chords;

  /// `|:` abre uma repetição neste compasso.
  final bool repeatStart;

  /// Quantas vezes se toca a repetição que `:|` fecha aqui (2, ou o `x3`).
  /// `null` se o compasso não fecha nenhuma.
  final int? repeatTimes;

  /// A casa do compasso (1 ou 2); `null` fora de casa.
  final int? ending;
}

/// Uma seção (`A:`, `B:`): começa no compasso [firstBar] e vai até a próxima.
@immutable
class ChartSection {
  const ChartSection({required this.label, required this.firstBar});

  final String label;

  /// Índice, em [ChordChart.bars], do primeiro compasso da seção.
  final int firstBar;

  @override
  bool operator ==(Object other) =>
      other is ChartSection &&
      other.label == label &&
      other.firstBar == firstBar;

  @override
  int get hashCode => Object.hash(label, firstBar);
}

/// Um compasso na ordem em que se toca: qual compasso escrito é, e em que volta.
@immutable
class PlayedBar {
  const PlayedBar({required this.writtenBar, required this.chorus});

  /// Índice em [ChordChart.bars].
  final int writtenBar;

  /// A volta: 1 na primeira vez; 2 na segunda, ou na 2ª casa.
  final int chorus;

  @override
  bool operator ==(Object other) =>
      other is PlayedBar &&
      other.writtenBar == writtenBar &&
      other.chorus == chorus;

  @override
  int get hashCode => Object.hash(writtenBar, chorus);

  @override
  String toString() => '$writtenBar×$chorus';
}

/// Um acorde no tempo. [barOccurrence] é o índice na forma tocada; os tempos
/// (`startBeat`, `beats`) são de tempo de compasso (ver [ChordChart.time]),
/// contados desde o começo da forma tocada.
@immutable
class ChartSlot {
  const ChartSlot({
    required this.barOccurrence,
    required this.writtenBar,
    required this.startBeat,
    required this.beats,
    required this.chord,
    required this.degree,
  });

  final int barOccurrence;
  final int writtenBar;
  final double startBeat;
  final double beats;

  /// `null` no `N.C.`.
  final ChordSymbol? chord;
  final String degree;

  @override
  bool operator ==(Object other) =>
      other is ChartSlot &&
      other.barOccurrence == barOccurrence &&
      other.writtenBar == writtenBar &&
      other.startBeat == startBeat &&
      other.beats == beats &&
      other.chord == chord &&
      other.degree == degree;

  @override
  int get hashCode =>
      Object.hash(barOccurrence, writtenBar, startBeat, beats, chord, degree);
}

/// Uma grade de acordes: o tom, o compasso e os compassos como escritos.
@immutable
class ChordChart {
  const ChordChart({
    required this.key,
    required this.time,
    required this.bars,
    this.sections = const [],
  });

  /// Lê o texto de uma grade (ver o cabeçalho do arquivo). Devolve `null` e
  /// chama [error] com a mensagem e a coluna (na linha) de cada erro.
  static ChordChart? parse(
    String text, {
    required KeySpec key,
    String time = '4/4',
    void Function(String error, int col)? error,
  }) {
    if (!_timePattern.hasMatch(time)) {
      error?.call(
        'o compasso `$time` não é um que a grade conhece (use 4/4, 3/4, '
        '2/4, 6/8, 12/8 ou C).',
        1,
      );
      return null;
    }
    final reader = _ChartReader(key, error);
    reader.read(text);
    return reader.result(time);
  }

  /// A grade de uma progressão da biblioteca (EX01), no tom [key]. Com [bars],
  /// a progressão se repete até completar esse número de compassos.
  /// Lança [ArgumentError] se a biblioteca não tem a progressão [name].
  static ChordChart fromProgression(
    String name, {
    required KeySpec key,
    String time = '4/4',
    int? bars,
  }) {
    final progression = progressionNamed(name);
    if (progression == null) {
      throw ArgumentError('a biblioteca não tem a progressão `$name`.');
    }
    final written = [
      for (final degrees in progression.bars)
        ChartBar(
          chords: [
            for (final word in degrees)
              _degreeChord(ChordDegree.parse(word)!, key),
          ],
        ),
    ];
    final count = bars ?? written.length;
    return ChordChart(
      key: key,
      time: time,
      bars: [for (var k = 0; k < count; k++) written[k % written.length]],
    );
  }

  final KeySpec key;

  /// `4/4`, `3/4`, `2/4`, `6/8`, `12/8` (ou `C`, o 4/4).
  final String time;

  /// Os compassos como escritos, com as marcas de repetição e de casa.
  final List<ChartBar> bars;

  /// As seções (`A:`, `B:`), na ordem. Vazia se a grade não tem rótulos.
  final List<ChartSection> sections;

  /// Os tempos de um compasso: o numerador, e nos compostos (6/8, 12/8) um
  /// tempo por três colcheias.
  int get beatsPerBar => _beatsOf(time);

  /// A forma tocada: os compassos na ordem de execução, com as repetições e as
  /// casas expandidas. Cada um traz o índice escrito e a volta.
  List<PlayedBar> expand() {
    final played = <PlayedBar>[];
    var i = 0;
    while (i < bars.length) {
      // Uma região vai de [i] até o compasso que fecha a repetição (`:|`); um
      // `|:` no meio dela corta antes.
      var close = -1;
      var k = i;
      for (; k < bars.length; k++) {
        if (k > i && bars[k].repeatStart) break;
        if (bars[k].repeatTimes != null) {
          close = k;
          break;
        }
      }
      if (close < 0) {
        // Trecho sem repetição: toca uma vez (e as casas, como estão).
        for (var j = i; j < k; j++) {
          played.add(PlayedBar(writtenBar: j, chorus: bars[j].ending ?? 1));
        }
        i = k;
        continue;
      }
      final times = bars[close].repeatTimes!;
      for (var pass = 1; pass <= times; pass++) {
        for (var j = i; j <= close; j++) {
          final ending = bars[j].ending;
          if (ending == null || ending == pass) {
            played.add(PlayedBar(writtenBar: j, chorus: pass));
          }
        }
      }
      i = close + 1;
      // A 2ª casa, depois do fecho, toca uma vez, na última volta.
      while (i < bars.length && bars[i].ending == 2 && !bars[i].repeatStart) {
        played.add(PlayedBar(writtenBar: i, chorus: 2));
        i++;
      }
    }
    return played;
  }

  /// Os acordes no tempo, na ordem em que se tocam. Numa bar com `n` fatias,
  /// se `n` cabe nos tempos, as primeiras ganham o tempo que sobra (`F G` em
  /// 3/4 dá 2 + 1); se não cabe, cada fatia leva a parte igual do compasso.
  List<ChartSlot> slots() {
    final result = <ChartSlot>[];
    var beat = 0.0;
    final played = expand();
    for (var occurrence = 0; occurrence < played.length; occurrence++) {
      final written = played[occurrence].writtenBar;
      final chords = bars[written].chords;
      final shares = sharesOf(written);
      for (var k = 0; k < chords.length; k++) {
        result.add(
          ChartSlot(
            barOccurrence: occurrence,
            writtenBar: written,
            startBeat: beat,
            beats: shares[k],
            chord: chords[k].chord,
            degree: chords[k].degree,
          ),
        );
        beat += shares[k];
      }
    }
    return result;
  }

  /// Quantos tempos leva cada acorde do compasso escrito [writtenBar] (a mesma
  /// conta de [slots]).
  List<double> sharesOf(int writtenBar) =>
      _shares(bars[writtenBar].chords.length, beatsPerBar);

  /// A mesma grade, escrita no tom [other]: cada cifra anda com o tom (C para
  /// E♭ leva F a A♭, e não a G♯), e o grau fica igual.
  ChordChart transposedTo(KeySpec other) => ChordChart(
    key: other,
    time: time,
    sections: sections,
    bars: [
      for (final bar in bars)
        ChartBar(
          chords: [
            for (final chord in bar.chords)
              ChartChord(
                chord: chord.chord == null
                    ? null
                    : _transpose(chord.chord!, key, other),
                degree: chord.degree,
              ),
          ],
          repeatStart: bar.repeatStart,
          repeatTimes: bar.repeatTimes,
          ending: bar.ending,
        ),
    ],
  );
}

final _timePattern = RegExp(r'^(\d+)/(2|4|8)$|^C$');

int _beatsOf(String time) {
  if (time == 'C') return 4;
  final parts = time.split('/');
  final top = int.parse(parts[0]);
  return parts[1] == '8' && top % 3 == 0 ? top ~/ 3 : top;
}

/// As fatias de um compasso de [beats] tempos, com [count] acordes.
List<double> _shares(int count, int beats) {
  if (count <= beats) {
    final base = beats ~/ count;
    final extra = beats % count;
    return [
      for (var k = 0; k < count; k++) (k < extra ? base + 1 : base).toDouble(),
    ];
  }
  return List.filled(count, beats / count);
}

/// O acorde de um grau no tom, com o grau escrito junto.
ChartChord _degreeChord(ChordDegree degree, KeySpec key) =>
    ChartChord(chord: degree.inKey(key), degree: degree.label);

/// O grau de uma cifra no tom: `I`, `ii7`, `bVII`, `Imaj7`. A maiúscula é o
/// acorde com 3ª maior; a minúscula, com 3ª menor (e o diminuto).
String _romanOf(ChordSymbol chord, KeySpec key) {
  const prefixes = ['', 'b', '', 'b', '', '', '#', '', 'b', '', 'b', ''];
  const romans = [
    'I',
    'II',
    'II',
    'III',
    'III',
    'IV',
    'IV',
    'V',
    'VI',
    'VI',
    'VII',
    'VII',
  ];
  final steps = _mod12(chord.root - key.tonic);
  final roman = chord.third == 3 ? romans[steps].toLowerCase() : romans[steps];
  return '${prefixes[steps]}$roman${_suffixOf(chord.quality)}';
}

String _suffixOf(ChordQuality quality) => switch (quality) {
  ChordQuality.major || ChordQuality.minor => '',
  ChordQuality.dominant7 || ChordQuality.minor7 => '7',
  ChordQuality.major7 || ChordQuality.minorMajor7 => 'maj7',
  ChordQuality.major6 || ChordQuality.minor6 => '6',
  ChordQuality.diminished => '°',
  ChordQuality.diminished7 => '°7',
  ChordQuality.halfDiminished7 => 'ø7',
  ChordQuality.augmented => '+',
  ChordQuality.sus2 => 'sus2',
  ChordQuality.sus4 => 'sus4',
  ChordQuality.dominant7sus4 => '7sus4',
  ChordQuality.power => '5',
};

/// A cifra [chord] com a fundamental e o baixo levados de [from] para [to].
/// A letra de cada nota anda com a letra da tônica: é isso que faz C→E♭
/// levar F a A♭.
ChordSymbol _transpose(ChordSymbol chord, KeySpec from, KeySpec to) {
  final semitones = _mod12(to.tonic - from.tonic);
  final root = _mod12(chord.root + semitones);
  final bass = chord.bass == null ? null : _mod12(chord.bass! + semitones);
  return ChordSymbol(
    root: root,
    rootSpelling: _respell(chord.rootSpelling, from, to, root),
    quality: chord.quality,
    tensions: chord.tensions,
    bass: bass,
    bassSpelling: chord.bassSpelling == null
        ? null
        : _respell(chord.bassSpelling!, from, to, bass!),
  );
}

/// A grafia de uma nota de [pitch] (classe de altura) no tom [to], com a letra
/// que a nota [spelling] (no tom [from]) ocupa a partir da tônica.
String _respell(String spelling, KeySpec from, KeySpec to, int pitch) {
  const letters = 'CDEFGAB';
  const naturals = [0, 2, 4, 5, 7, 9, 11];
  final steps =
      (letters.indexOf(spelling[0]) - letters.indexOf(from.spelling[0]) + 7) %
      7;
  final index = (letters.indexOf(to.spelling[0]) + steps) % 7;
  var alter = _mod12(pitch - naturals[index]);
  if (alter > 6) alter -= 12;
  final accidental = alter >= 0 ? '#' * alter : 'b' * -alter;
  return '${letters[index]}$accidental';
}

int _mod12(int x) => ((x % 12) + 12) % 12;

/// Um compasso em montagem. `:|` acha o compasso já fechado quando ele está
/// vazio (`| C |` com o `:|` depois do espaço), por isso o fecho é mutável.
class _Bar {
  _Bar(
    this.chords, {
    required this.repeatStart,
    required this.repeatStartCol,
    required this.ending,
  });

  final List<ChartChord> chords;
  final bool repeatStart;
  final int repeatStartCol;
  final int? ending;
  int? repeatTimes;
}

/// Lê o texto da grade. Cada erro sai no callback na hora, com a coluna; o
/// resultado é `null` se houve algum.
class _ChartReader {
  _ChartReader(this._key, this._error);

  final KeySpec _key;
  final void Function(String, int)? _error;

  final _bars = <_Bar>[];
  final _sections = <ChartSection>[];
  var _failed = false;

  var _current = <ChartChord>[];
  var _percent = false;
  ChartChord? _last;
  int? _ending;
  int? _repeatStartCol;
  String? _sectionNext;

  void read(String text) {
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      _line(line);
    }
    _push();
    if (_repeatStartCol != null) {
      _fail('`|:` sem compasso depois', _repeatStartCol!);
    }
    if (_bars.isEmpty && !_failed) {
      _fail('a grade não tem compassos', 1);
    }
    var open = -1;
    for (final bar in _bars) {
      if (bar.repeatStart) {
        if (open >= 0) {
          _fail('`|:` dentro de outra repetição', bar.repeatStartCol);
        }
        open = bar.repeatStartCol;
      }
      if (bar.repeatTimes != null) open = -1;
    }
    if (open >= 0) _fail('`|:` sem um `:|` que a feche', open);
  }

  /// A grade lida, ou `null` se houve erro.
  ChordChart? result(String time) {
    if (_failed) return null;
    return ChordChart(
      key: _key,
      time: time,
      sections: _sections,
      bars: [
        for (final bar in _bars)
          ChartBar(
            chords: bar.chords,
            repeatStart: bar.repeatStart,
            repeatTimes: bar.repeatTimes,
            ending: bar.ending,
          ),
      ],
    );
  }

  void _fail(String message, int col) {
    _failed = true;
    _error?.call(message, col);
  }

  void _line(String line) {
    var i = 0;
    final label = RegExp(r'^\s*([A-Z]):\s*').firstMatch(line);
    if (label != null) {
      _push();
      _sectionNext = label.group(1);
      i = label.end;
    }
    while (i < line.length) {
      final c = line[i];
      final col = i + 1;
      if (c == ' ' || c == '\t') {
        i++;
      } else if (line.startsWith('|:', i)) {
        _push();
        _repeatStartCol = col;
        i += 2;
      } else if (line.startsWith(':|', i)) {
        i += 2;
        final times = RegExp(r'^\s*x(\d+)').firstMatch(line.substring(i));
        var repeat = 2;
        if (times != null) {
          repeat = int.parse(times.group(1)!);
          i += times.end;
        }
        _endRepeat(repeat, col);
      } else if (c == '|') {
        _push();
        i++;
        if (i < line.length && line[i] == '|') i++; // `||`, a barra dupla
      } else if (c == '[') {
        final casa = RegExp(r'^\[([12])').firstMatch(line.substring(i));
        if (casa == null) {
          _fail('`[` pede a casa: `[1` ou `[2`', col);
          i++;
        } else {
          _push();
          _ending = int.parse(casa.group(1)!);
          i += casa.end;
        }
      } else if (c == ']') {
        _push();
        _ending = null;
        i++;
      } else {
        final end = _wordEnd(line, i);
        _word(line.substring(i, end), col);
        i = end;
      }
    }
  }

  /// Onde termina a palavra que começa em [start]: no espaço, numa barra, num
  /// colchete ou num `:|`.
  int _wordEnd(String line, int start) {
    var i = start;
    while (i < line.length) {
      final c = line[i];
      if (c == ' ' || c == '\t' || c == '|' || c == '[' || c == ']') break;
      if (c == ':' && i + 1 < line.length && line[i + 1] == '|') break;
      i++;
    }
    return i;
  }

  void _word(String word, int col) {
    if (_percent) {
      _fail('`%` ocupa o compasso inteiro: tire `$word`', col);
      return;
    }
    if (word == '%') {
      if (_current.isNotEmpty || _bars.isEmpty) {
        _fail(
          '`%` repete o compasso anterior: ponha-o sozinho num compasso',
          col,
        );
        return;
      }
      _current = List.of(_bars.last.chords);
      _percent = true;
      _last = _current.last;
      return;
    }
    if (word == '.') {
      if (_last == null) {
        _fail('`.` repete o acorde anterior, e não há um antes', col);
        return;
      }
      _add(_last!);
      return;
    }
    if (word == 'N.C.') {
      _add(const ChartChord(chord: null, degree: 'N.C.'));
      return;
    }
    final chord = ChordSymbol.parse(word);
    if (chord != null) {
      _add(ChartChord(chord: chord, degree: _romanOf(chord, _key)));
      return;
    }
    final degree = ChordDegree.parse(word);
    if (degree != null) {
      _add(_degreeChord(degree, _key));
      return;
    }
    _fail(
      '`$word` não é uma cifra (como `Am` ou `F7`) nem um grau (como `ii7`)',
      col,
    );
  }

  void _add(ChartChord chord) {
    _current.add(chord);
    _last = chord;
  }

  /// Fecha o compasso em montagem (se tem acordes). Com [repeatTimes], é o
  /// `:|`; e uma casa aberta acaba aqui.
  void _push({int? repeatTimes}) {
    if (_current.isEmpty) return;
    if (_sectionNext != null) {
      _sections.add(ChartSection(label: _sectionNext!, firstBar: _bars.length));
      _sectionNext = null;
    }
    _bars.add(
      _Bar(
        _current,
        repeatStart: _repeatStartCol != null,
        repeatStartCol: _repeatStartCol ?? 0,
        ending: _ending,
      )..repeatTimes = repeatTimes,
    );
    _current = [];
    _percent = false;
    _repeatStartCol = null;
  }

  void _endRepeat(int times, int col) {
    if (_current.isNotEmpty) {
      _push(repeatTimes: times);
    } else if (_bars.isNotEmpty) {
      _bars.last.repeatTimes = times;
    } else {
      _fail('`:|` antes de qualquer compasso', col);
    }
    _ending = null;
  }
}
