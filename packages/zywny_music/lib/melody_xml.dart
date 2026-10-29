// EX16 — a melodia de um `.musicxml` do autor, lida em Dart puro (sem Verovio):
// as notas com a hora em semínimas, os compassos, a armadura e as marcas de
// troca de acorde (`chg`). Serve ao validador do curso e ao `harmonize`.
//
// O que se lê: a primeira parte, e nela as notas de voz 1 (ou sem voz). Um
// acorde na melodia fica com a nota mais aguda; a apojatura (`grace`) não
// entra; a ligadura (`tie`) de notas iguais vira uma nota só. Outras vozes
// avançam o tempo (com `backup`/`forward`) mas não são lidas.

import 'package:meta/meta.dart';

/// Uma nota da melodia: a altura MIDI, a hora e a duração em semínimas (1 é a
/// semínima, qualquer que seja o compasso), e o `xml:id` da nota no arquivo.
@immutable
class MelodyNote {
  const MelodyNote({
    required this.pitch,
    required this.start,
    required this.beats,
    this.id,
  });

  final int pitch;
  final double start;
  final double beats;

  /// O `xml:id` (ou `id`) da nota no arquivo, quando ele tem; é o que a tela
  /// usa para destacar a nota. `null` quando o arquivo não o dá.
  final String? id;
}

/// Um compasso do arquivo: onde começa e quantas semínimas tem, e a fórmula.
@immutable
class MelodyMeasure {
  const MelodyMeasure({
    required this.start,
    required this.beats,
    required this.time,
  });

  final double start;
  final double beats;

  /// A fórmula do compasso (`4/4`, `3/4`…).
  final String time;
}

/// Uma cifra do arquivo (`<harmony>`, EX17): a hora em semínimas desde o começo
/// da peça e o nome da cifra na grafia da EX01 (`C7M`, `Dm7(b5)`, `G/B`), ou
/// `null` quando o tipo de acorde do arquivo não tem nome nessa grafia.
@immutable
class MelodyHarmony {
  const MelodyHarmony({
    required this.start,
    required this.symbol,
    required this.kind,
  });

  final double start;

  /// A cifra na grafia da EX01, ou `null` (ver [kind]).
  final String? symbol;

  /// O tipo de acorde como o arquivo o escreveu (`major-seventh`), para a
  /// mensagem de erro quando [symbol] é `null`.
  final String kind;
}

/// A melodia lida: as notas, os compassos, a armadura, as marcas `chg` e as
/// cifras (`<harmony>`, vazias nos arquivos sem cifra).
@immutable
class MelodyScore {
  const MelodyScore({
    required this.notes,
    required this.measures,
    required this.changes,
    required this.fifths,
    required this.minor,
    this.harmonies = const [],
  });

  /// As cifras da partitura, em ordem de hora (EX17).
  final List<MelodyHarmony> harmonies;

  /// As notas, em ordem de hora.
  final List<MelodyNote> notes;

  /// Os compassos, em ordem.
  final List<MelodyMeasure> measures;

  /// As marcas de troca de acorde (`<words>chg</words>`), em semínimas desde o
  /// começo, em ordem.
  final List<double> changes;

  /// A armadura (`<key><fifths>`): quantos sustenidos (negativo, bemóis); `null`
  /// quando o arquivo não tem `<key>`.
  final int? fifths;

  /// `<mode>minor</mode>`: a armadura é de menor (a tônica fica 3 semitons
  /// abaixo da maior).
  final bool minor;

  /// A fórmula do primeiro compasso (`4/4` se o arquivo não tem `<time>`).
  String get time => measures.isEmpty ? '4/4' : measures.first.time;

  /// O compasso (base 0) que contém a hora [at], em semínimas (EX17).
  int measureAt(double at) {
    var found = 0;
    for (var m = 0; m < measures.length; m++) {
      if (measures[m].start <= at + 1e-9) found = m;
    }
    return found;
  }

  /// A classe de altura da tônica (0 a 11), ou `null` sem armadura.
  int? get tonicPc {
    final f = fifths;
    if (f == null) return null;
    final major = _mod12(f * 7);
    return minor ? _mod12(major + 9) : major;
  }

  static int _mod12(int x) => ((x % 12) + 12) % 12;
}

/// Lê o MusicXML [xml] (`score-partwise`). Devolve `null` com [error] se não é
/// uma partitura com parte, ou se a parte não tem nota de melodia.
MelodyScore? readMelodyXml(String xml, {void Function(String message)? error}) {
  final doc = _parseXml(xml);
  final root = doc.child('score-partwise');
  if (root == null) {
    error?.call('o arquivo não é um MusicXML `score-partwise`');
    return null;
  }
  final part = root.child('part');
  if (part == null) {
    error?.call('o arquivo não tem nenhuma parte (`<part>`)');
    return null;
  }

  final notes = <MelodyNote>[];
  final measures = <MelodyMeasure>[];
  final changes = <double>[];
  int? fifths;
  var minor = false;
  var divisions = 1.0;
  var beats = 4;
  var beatType = 4;
  var measureStart = 0.0;
  final harmonies = <MelodyHarmony>[];

  for (final measure in part.childrenNamed('measure')) {
    final nominal = beats * 4 / beatType;
    var pos = 0.0; // em semínimas, dentro do compasso
    var reached = 0.0;
    // Onde começou a última nota de voz 1, para o acorde na melodia.
    double? lastStart;
    for (final node in measure.children) {
      switch (node.name) {
        case 'attributes':
          final d = node.child('divisions');
          if (d != null) divisions = _num(d.text, divisions);
          final time = node.child('time');
          if (time != null) {
            beats = int.tryParse(time.child('beats')?.text ?? '') ?? beats;
            beatType =
                int.tryParse(time.child('beat-type')?.text ?? '') ?? beatType;
          }
          final key = node.child('key');
          if (key != null) {
            fifths = int.tryParse(key.child('fifths')?.text ?? '') ?? fifths;
            minor = key.child('mode')?.text == 'minor';
          }
        case 'harmony':
          // A cifra vale do ponto em que está (antes da nota que ela acompanha).
          harmonies.add(
            MelodyHarmony(
              start: measureStart + pos,
              symbol: _symbolOf(node),
              kind: node.child('kind')?.text ?? '',
            ),
          );
        case 'direction':
          for (final words in node.descendants('words')) {
            if (words.text.toLowerCase() == 'chg') {
              changes.add(measureStart + pos);
            }
          }
        case 'backup':
          pos -= _num(node.child('duration')?.text ?? '0', 0) / divisions;
        case 'forward':
          pos += _num(node.child('duration')?.text ?? '0', 0) / divisions;
        case 'note':
          final grace = node.child('grace') != null;
          if (grace) break;
          final chord = node.child('chord') != null;
          final duration =
              _num(node.child('duration')?.text ?? '0', 0) / divisions;
          final start = chord && lastStart != null ? lastStart : pos;
          final voice = node.child('voice')?.text ?? '1';
          final pitch = _pitchOf(node.child('pitch'));
          if (pitch != null && voice == '1') {
            _addNote(
              notes,
              pitch: pitch,
              start: measureStart + start,
              beats: duration,
              node: node,
              chord: chord,
            );
            lastStart = start;
          }
          if (!chord) {
            pos += duration;
            if (pos > reached) reached = pos;
          }
        default:
          break;
      }
    }
    measures.add(
      MelodyMeasure(
        start: measureStart,
        beats: nominal,
        time: '$beats/$beatType',
      ),
    );
    // Um compasso de anacruse (`implicit="yes"`) é só o que tem nota.
    final implicit = measure.attrs['implicit'] == 'yes';
    measureStart += implicit ? reached : nominal;
  }

  if (notes.isEmpty) {
    error?.call('a parte não tem nenhuma nota de melodia (voz 1)');
    return null;
  }
  return MelodyScore(
    notes: notes,
    measures: measures,
    changes: changes,
    fifths: fifths,
    minor: minor,
    harmonies: harmonies,
  );
}

/// O sufixo da cifra de cada tipo de acorde do MusicXML, na grafia da EX01. Os
/// tipos que não estão aqui não têm nome nessa grafia (a cifra fica `null`).
const _kindSuffix = {
  'major': '',
  'minor': 'm',
  'augmented': '+',
  'diminished': 'dim',
  'dominant': '7',
  'major-seventh': 'maj7',
  'minor-seventh': 'm7',
  'diminished-seventh': 'dim7',
  'half-diminished': 'm7b5',
  'major-sixth': '6',
  'minor-sixth': 'm6',
  'dominant-ninth': '9',
  'major-ninth': 'maj9',
  'minor-ninth': 'm9',
  'dominant-11th': '11',
  'dominant-13th': '13',
  'suspended-second': 'sus2',
  'suspended-fourth': 'sus4',
};

/// A cifra de um `<harmony>` na grafia da EX01: a fundamental, o sufixo (o
/// `text` do `<kind>`, se o arquivo o dá; senão o tipo) e o baixo. `null` sem
/// fundamental ou com um tipo que não tem nome.
String? _symbolOf(_Node harmony) {
  final root = harmony.child('root');
  final step = root?.child('root-step')?.text;
  if (step == null || step.isEmpty) return null;
  final kind = harmony.child('kind');
  final text = kind?.attrs['text']?.trim() ?? '';
  final suffix = text.isNotEmpty ? text : _kindSuffix[kind?.text];
  if (suffix == null) return null;
  final bass = harmony.child('bass')?.child('bass-step')?.text;
  final buffer = StringBuffer()
    ..write(step)
    ..write(_alterText(root?.child('root-alter')?.text))
    ..write(suffix);
  if (bass != null && bass.isNotEmpty) {
    final bassAlter = harmony.child('bass')?.child('bass-alter')?.text;
    buffer
      ..write('/')
      ..write(bass)
      ..write(_alterText(bassAlter));
  }
  return buffer.toString();
}

/// O acidente de um `<root-alter>` ou `<bass-alter>` na grafia da cifra (`#`,
/// `b`), ou vazio.
String _alterText(String? alter) {
  final value = double.tryParse(alter?.trim() ?? '') ?? 0;
  final semitones = value.round();
  if (semitones == 0) return '';
  return semitones > 0 ? '#' * semitones : 'b' * -semitones;
}

/// Acrescenta uma nota, ou a funde com a anterior (ligadura, ou acorde na
/// melodia: fica a mais aguda).
void _addNote(
  List<MelodyNote> notes, {
  required int pitch,
  required double start,
  required double beats,
  required _Node node,
  required bool chord,
}) {
  final id = node.attrs['xml:id'] ?? node.attrs['id'];
  if (chord && notes.isNotEmpty && (notes.last.start - start).abs() < 1e-9) {
    final last = notes.last;
    if (pitch > last.pitch) {
      notes[notes.length - 1] = MelodyNote(
        pitch: pitch,
        start: last.start,
        beats: last.beats,
        id: id ?? last.id,
      );
    }
    return;
  }
  // A ligadura que chega: a nota anterior (da mesma altura, colada) soa junto.
  if (_tieType(node) == 'stop' && notes.isNotEmpty) {
    final last = notes.last;
    final contiguous = (last.start + last.beats - start).abs() < 1e-9;
    if (contiguous && last.pitch == pitch) {
      notes[notes.length - 1] = MelodyNote(
        pitch: pitch,
        start: last.start,
        beats: last.beats + beats,
        id: last.id,
      );
      return;
    }
  }
  notes.add(MelodyNote(pitch: pitch, start: start, beats: beats, id: id));
}

/// O tipo da ligadura da nota (`start` ou `stop`), o de `<tie>`.
String? _tieType(_Node node) {
  for (final tie in node.childrenNamed('tie')) {
    final type = tie.attrs['type'];
    if (type != null) return type;
  }
  return null;
}

/// A altura MIDI de um `<pitch>`: `step`, `alter` (semitons, pode ser
/// fracionário) e `octave` (com dó central = 4). `null` sem altura escrita.
int? _pitchOf(_Node? pitch) {
  if (pitch == null) return null;
  final step = pitch.child('step')?.text;
  final octave = int.tryParse(pitch.child('octave')?.text ?? '');
  const naturals = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  final pc = step == null ? null : naturals[step];
  if (pc == null || octave == null) return null;
  final alter = double.tryParse(pitch.child('alter')?.text ?? '0') ?? 0;
  return (octave + 1) * 12 + pc + alter.round();
}

double _num(String text, double fallback) =>
    double.tryParse(text.trim()) ?? fallback;

// ----- um leitor de XML mínimo: as tags, os atributos e o texto -------------

/// Um elemento: o nome, os atributos, os filhos e o texto solto dele.
class _Node {
  _Node(this.name, this.attrs);

  final String name;
  final Map<String, String> attrs;
  final List<_Node> children = [];
  final StringBuffer _text = StringBuffer();

  String get text => _unescape(_text.toString()).trim();

  _Node? child(String tag) {
    for (final c in children) {
      if (c.name == tag) return c;
    }
    return null;
  }

  Iterable<_Node> childrenNamed(String tag) =>
      children.where((c) => c.name == tag);

  Iterable<_Node> descendants(String tag) sync* {
    for (final c in children) {
      if (c.name == tag) yield c;
      yield* c.descendants(tag);
    }
  }
}

// As aspas simples saem como `\x27` para caber num texto raw.
final _tagPattern = RegExp(
  r'<(/?)([A-Za-z_][\w.:-]*)((?:\s+[\w.:-]+\s*=\s*(?:"[^"]*"|\x27[^\x27]*\x27))*)\s*(/?)>'
  r'|<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<![^>]*>|([^<]+)',
);
final _attrPattern = RegExp(
  r'([\w.:-]+)\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27)',
);

_Node _parseXml(String xml) {
  final root = _Node('#doc', const {});
  final stack = <_Node>[root];
  for (final m in _tagPattern.allMatches(xml)) {
    final text = m.group(5);
    if (text != null) {
      stack.last._text.write(text);
      continue;
    }
    final name = m.group(2);
    if (name == null) continue; // comentário, instrução ou DOCTYPE
    if (m.group(1) == '/') {
      if (stack.length > 1) stack.removeLast();
      continue;
    }
    final attrs = <String, String>{
      for (final a in _attrPattern.allMatches(m.group(3) ?? ''))
        a.group(1)!: a.group(2) ?? a.group(3) ?? '',
    };
    final node = _Node(name, attrs);
    stack.last.children.add(node);
    if (m.group(4) != '/') stack.add(node);
  }
  return root;
}

String _unescape(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
