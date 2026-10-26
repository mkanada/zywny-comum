import 'package:meta/meta.dart';

/// Se o `°` sozinho é diminuto com sétima (grafia brasileira) ou tríade
/// diminuta (americana). Falso: `C°` é a tríade e `C°7` a sétima, nas duas
/// grafias (D-EXE-CIFRA; EX01).
const kDegreeSignMeansDim7 = false;

/// A qualidade "de base" do acorde; as extensões vêm à parte.
enum ChordQuality {
  major,
  minor,
  diminished,
  augmented,
  dominant7,
  major7,
  minor7,
  halfDiminished7,
  diminished7,
  minorMajor7,
  major6,
  minor6,
  sus2,
  sus4,
  dominant7sus4,
  power, // C5
}

/// Uma extensão ou alteração: 9, b9, #9, 11, #11, 13, b13, add9, b5, #5.
enum ChordTension {
  nine,
  flat9,
  sharp9,
  eleven,
  sharp11,
  thirteen,
  flat13,
  add9,
  add11,
  flat5,
  sharp5,
  omit3,
  omit5,
}

/// Como a cifra é escrita: americana (`Cmaj7`, `Cm7b5`) ou brasileira
/// (`C7M`, `Cm7(b5)`). O leitor aceita as duas.
enum ChordNotation { american, brazilian }

/// Um acorde lido de uma cifra: fundamental, qualidade, extensões e baixo.
///
/// Os intervalos são em semitons a partir da fundamental; as classes de
/// altura, de 0 (Dó) a 11 (Si).
@immutable
class ChordSymbol {
  const ChordSymbol({
    required this.root,
    required this.rootSpelling,
    required this.quality,
    this.tensions = const {},
    this.bass,
    this.bassSpelling,
  });

  /// Lê `Am7`, `C7M`, `Cm7(b5)`, `F/G`, `Bb7(#11)`, `C6/9`, `C7alt`.
  /// Devolve `null` e chama [error] com a mensagem se não entende.
  static ChordSymbol? parse(String text, {void Function(String)? error}) {
    final source = text.trim().replaceAll('♯', '#').replaceAll('♭', 'b');
    if (source.isEmpty) {
      error?.call('Cifra vazia: escreva a fundamental, como C ou Am7.');
      return null;
    }
    final root = _rootPattern.firstMatch(source);
    if (root == null) {
      error?.call(
        '`$text`: a fundamental é de A a G, com # ou b (como F# ou Bb).',
      );
      return null;
    }
    var body = source.substring(root.end);
    final slash = _bassPattern.firstMatch(body);
    if (slash != null) body = body.substring(0, slash.start);

    var quality = ChordQuality.major;
    final tensions = <ChordTension>{};
    if (body == 'alt' || body == '7alt') {
      quality = ChordQuality.dominant7;
      tensions.addAll(_alt);
    } else {
      final token = _qualityTokens.firstWhere((t) => body.startsWith(t.$1));
      quality = token.$2;
      if (token.$1 == '°' && kDegreeSignMeansDim7) {
        quality = ChordQuality.diminished7;
      }
      final tail = body.substring(token.$1.length);
      final clean = tail.replaceAll(RegExp(r'[(),/]'), '');
      var at = 0;
      while (at < clean.length) {
        final match = _tensionPattern.matchAsPrefix(clean, at);
        final tension = match == null ? null : _tensionFromText[match.group(0)];
        if (tension == null) {
          error?.call('`$text`: não entendi `${clean.substring(at)}`.');
          return null;
        }
        tensions.add(tension);
        at = match!.end;
      }
    }

    // `C9` é `C7(9)`, e `Cm9` é `Cm7(9)`: a nona pede a sétima.
    final hasNumber =
        tensions.contains(ChordTension.nine) ||
        tensions.contains(ChordTension.eleven) ||
        tensions.contains(ChordTension.thirteen);
    if (hasNumber && quality == ChordQuality.major) {
      quality = ChordQuality.dominant7;
    }
    if (hasNumber && quality == ChordQuality.minor) {
      quality = ChordQuality.minor7;
    }
    // A 11ª e a 13ª pedem a 9ª.
    if (tensions.contains(ChordTension.eleven) ||
        tensions.contains(ChordTension.thirteen)) {
      tensions.add(ChordTension.nine);
    }

    final slashLetter = slash?.group(1);
    final slashAccidental = slash?.group(2) ?? '';
    return ChordSymbol(
      root: _pitchClass(root.group(1)!, root.group(2)!),
      rootSpelling: root.group(1)! + root.group(2)!,
      quality: quality,
      tensions: tensions,
      bass: slashLetter == null
          ? null
          : _pitchClass(slashLetter, slashAccidental),
      bassSpelling: slashLetter == null ? null : slashLetter + slashAccidental,
    );
  }

  /// Fundamental, de 0 (Dó) a 11 (Si).
  final int root;

  /// A grafia da fundamental, com `#` ou `b` (`C`, `Db`, `F#`).
  final String rootSpelling;
  final ChordQuality quality;
  final Set<ChordTension> tensions;

  /// Baixo da inversão (`F/G` tem `7`); `null` quando é a fundamental.
  final int? bass;
  final String? bassSpelling;

  /// A 3ª do acorde, em semitons (a 2ª na sus2, a 4ª na sus4); `null` no
  /// power chord. Não muda com `omit3`: é a 3ª da qualidade.
  int? get third => switch (quality) {
    ChordQuality.major ||
    ChordQuality.augmented ||
    ChordQuality.dominant7 ||
    ChordQuality.major7 ||
    ChordQuality.major6 => 4,
    ChordQuality.minor ||
    ChordQuality.diminished ||
    ChordQuality.halfDiminished7 ||
    ChordQuality.diminished7 ||
    ChordQuality.minor7 ||
    ChordQuality.minorMajor7 ||
    ChordQuality.minor6 => 3,
    ChordQuality.sus2 => 2,
    ChordQuality.sus4 || ChordQuality.dominant7sus4 => 5,
    ChordQuality.power => null,
  };

  /// A 5ª do acorde: 7, ou 6 e 8 com b5 e #5 (que trocam a 5ª).
  int get fifth {
    if (tensions.contains(ChordTension.flat5)) return 6;
    if (tensions.contains(ChordTension.sharp5)) return 8;
    return switch (quality) {
      ChordQuality.diminished ||
      ChordQuality.halfDiminished7 ||
      ChordQuality.diminished7 => 6,
      ChordQuality.augmented => 8,
      _ => 7,
    };
  }

  /// A 7ª do acorde (na 6ª, a 6ª é a 9 de voicing: 9); `null` na tríade.
  int? get seventh => switch (quality) {
    ChordQuality.dominant7 ||
    ChordQuality.dominant7sus4 ||
    ChordQuality.minor7 ||
    ChordQuality.halfDiminished7 => 10,
    ChordQuality.major7 || ChordQuality.minorMajor7 => 11,
    ChordQuality.diminished7 || ChordQuality.major6 || ChordQuality.minor6 => 9,
    _ => null,
  };

  /// Os intervalos de todas as notas do acorde, sem o baixo, de 0 a 11.
  Set<int> get intervals {
    final result = <int>{0};
    final third = this.third;
    if (third != null && !tensions.contains(ChordTension.omit3)) {
      result.add(third);
    }
    if (!tensions.contains(ChordTension.omit5)) result.add(fifth);
    final seventh = this.seventh;
    if (seventh != null) result.add(seventh);
    for (final tension in tensions) {
      final interval = _intervalOf(tension);
      if (interval != null) result.add(interval);
    }
    return {for (final i in result) _mod12(i)};
  }

  /// Classes de altura (0 a 11) de todas as notas, com o baixo incluído.
  Set<int> get pitchClasses {
    return {for (final i in intervals) _mod12(root + i), ?bass};
  }

  /// As notas que **precisam** estar (D-EXE-ACORDE). Com [omit5] (o padrão),
  /// a 5ª justa pode faltar nos acordes de sétima ou mais.
  Set<int> requiredPitchClasses({bool omit5 = true}) =>
      omit5 ? pitchClasses.difference(allowedPitchClasses()) : pitchClasses;

  /// Notas que podem faltar sem erro: a 5ª, num acorde de sétima ou mais.
  ///
  /// A fundamental **não** entra aqui: um voicing sem fundamental é uma
  /// decisão do exercício (EX02), não da cifra.
  Set<int> allowedPitchClasses() {
    final seventh = this.seventh;
    if (seventh == null || tensions.contains(ChordTension.omit5)) return {};
    return {_mod12(root + fifth)};
  }

  /// O grau de uma classe de altura, para a tela dizer "faltou a 3ª".
  String degreeOf(int pitchClass) {
    return switch (_mod12(pitchClass - root)) {
      0 => '1',
      1 => 'b9',
      2 => '9',
      3 => third == 3 ? 'b3' : '#9',
      4 => '3',
      5 => '11',
      6 => fifth == 6 ? 'b5' : '#11',
      7 => '5',
      8 => fifth == 8 ? '#5' : 'b13',
      9 => switch (quality) {
        ChordQuality.diminished7 => 'bb7',
        ChordQuality.major6 || ChordQuality.minor6 => '6',
        _ => '13',
      },
      10 => 'b7',
      _ => '7',
    };
  }

  /// A cifra escrita de volta, na grafia [notation].
  String label(ChordNotation notation) {
    final text = switch (notation) {
      ChordNotation.american => _american(),
      ChordNotation.brazilian => _brazilian(),
    };
    final bassSpelling = this.bassSpelling;
    return '$rootSpelling$text'
        '${bassSpelling == null ? '' : '/$bassSpelling'}';
  }

  /// Sem a grafia escolhida, a americana (é a padrão das cifras).
  @override
  String toString() => label(ChordNotation.american);

  bool get _isAlt =>
      quality == ChordQuality.dominant7 &&
      tensions.length == _alt.length &&
      tensions.containsAll(_alt);

  /// O número da extensão mais alta (13, 11 ou 9), que substitui a 7ª.
  String? get _number {
    if (tensions.contains(ChordTension.thirteen)) return '13';
    if (tensions.contains(ChordTension.eleven)) return '11';
    if (tensions.contains(ChordTension.nine)) return '9';
    return null;
  }

  /// As alterações e as que não são número (`b9`, `#11`, `add9`…).
  List<String> get _others => [
    for (final tension in ChordTension.values)
      if (tensions.contains(tension) && !_extensionNumbers.contains(tension))
        _textOf(tension),
  ];

  String _american() {
    if (_isAlt) return '7alt';
    final number = _number;
    var base = switch (quality) {
      ChordQuality.major => '',
      ChordQuality.minor => 'm',
      ChordQuality.diminished => 'dim',
      ChordQuality.augmented => 'aug',
      ChordQuality.dominant7 => '7',
      ChordQuality.major7 => 'maj7',
      ChordQuality.minor7 => 'm7',
      ChordQuality.halfDiminished7 => 'm7b5',
      ChordQuality.diminished7 => 'dim7',
      ChordQuality.minorMajor7 => 'mMaj7',
      ChordQuality.major6 => '6',
      ChordQuality.minor6 => 'm6',
      ChordQuality.sus2 => 'sus2',
      ChordQuality.sus4 => 'sus4',
      ChordQuality.dominant7sus4 => '7sus4',
      ChordQuality.power => '5',
    };
    if (number != null) {
      base = switch (quality) {
        ChordQuality.dominant7 => number,
        ChordQuality.major7 => 'maj$number',
        ChordQuality.minor7 => 'm$number',
        ChordQuality.minorMajor7 => 'mMaj$number',
        ChordQuality.major6 when number == '9' => '6/9',
        ChordQuality.minor6 when number == '9' => 'm6/9',
        _ => '$base$number',
      };
    }
    return '$base${_others.join()}';
  }

  String _brazilian() {
    final number = _number;
    final base = switch (quality) {
      ChordQuality.major => '',
      ChordQuality.minor => 'm',
      ChordQuality.diminished => '°',
      ChordQuality.augmented => '+',
      ChordQuality.dominant7 => '7',
      ChordQuality.major7 => '7M',
      ChordQuality.minor7 => 'm7',
      ChordQuality.halfDiminished7 => 'm7(b5)',
      ChordQuality.diminished7 => '°7',
      ChordQuality.minorMajor7 => 'm(maj7)',
      ChordQuality.major6 => '6',
      ChordQuality.minor6 => 'm6',
      ChordQuality.sus2 => 'sus2',
      ChordQuality.sus4 => '4',
      ChordQuality.dominant7sus4 => '7(4)',
      ChordQuality.power => '5',
    };
    final parts = [?number, ..._others];
    return parts.isEmpty ? base : '$base(${parts.join(',')})';
  }

  @override
  bool operator ==(Object other) =>
      other is ChordSymbol &&
      other.root == root &&
      other.rootSpelling == rootSpelling &&
      other.quality == quality &&
      other.bass == bass &&
      other.bassSpelling == bassSpelling &&
      other.tensions.length == tensions.length &&
      other.tensions.containsAll(tensions);

  @override
  int get hashCode => Object.hash(
    root,
    rootSpelling,
    quality,
    bass,
    bassSpelling,
    Object.hashAllUnordered(tensions),
  );
}

int _mod12(int x) => ((x % 12) + 12) % 12;

int _pitchClass(String letter, String accidental) => _mod12(
  _letterPitch[letter]! +
      (accidental == '#' ? 1 : (accidental == 'b' ? -1 : 0)),
);

/// Alturas das notas naturais, de C (0) a B (11).
const _letterPitch = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

final _rootPattern = RegExp(r'^([A-G])([#b]?)');
final _bassPattern = RegExp(r'/([A-G])([#b]?)$');
final _tensionPattern = RegExp(r'add9|add11|omit3|omit5|[b#]?(?:13|11|9|5)');

/// `alt` é a dominante com alterações: b9, #9, b5 e b13 (escolha registrada).
const _alt = {
  ChordTension.flat9,
  ChordTension.sharp9,
  ChordTension.flat5,
  ChordTension.flat13,
};

const _extensionNumbers = {
  ChordTension.nine,
  ChordTension.eleven,
  ChordTension.thirteen,
};

const _tensionFromText = {
  '9': ChordTension.nine,
  'b9': ChordTension.flat9,
  '#9': ChordTension.sharp9,
  '11': ChordTension.eleven,
  '#11': ChordTension.sharp11,
  '13': ChordTension.thirteen,
  'b13': ChordTension.flat13,
  'add9': ChordTension.add9,
  'add11': ChordTension.add11,
  'b5': ChordTension.flat5,
  '#5': ChordTension.sharp5,
  'omit3': ChordTension.omit3,
  'omit5': ChordTension.omit5,
};

String _textOf(ChordTension tension) => switch (tension) {
  ChordTension.nine => '9',
  ChordTension.flat9 => 'b9',
  ChordTension.sharp9 => '#9',
  ChordTension.eleven => '11',
  ChordTension.sharp11 => '#11',
  ChordTension.thirteen => '13',
  ChordTension.flat13 => 'b13',
  ChordTension.add9 => 'add9',
  ChordTension.add11 => 'add11',
  ChordTension.flat5 => 'b5',
  ChordTension.sharp5 => '#5',
  ChordTension.omit3 => 'omit3',
  ChordTension.omit5 => 'omit5',
};

/// Onde a tensão cai, em semitons a partir da fundamental. `null` quando ela
/// só muda a 5ª (b5, #5) ou tira uma nota (omit3, omit5).
int? _intervalOf(ChordTension tension) => switch (tension) {
  ChordTension.nine || ChordTension.add9 => 2,
  ChordTension.flat9 => 1,
  ChordTension.sharp9 => 3,
  ChordTension.eleven || ChordTension.add11 => 5,
  ChordTension.sharp11 => 6,
  ChordTension.thirteen => 9,
  ChordTension.flat13 => 8,
  _ => null,
};

/// O texto da qualidade, do mais longo para o mais curto. Vale a primeira
/// que começa a cifra; `''` (a tríade maior) fica por último.
final _qualityTokens = <(String, ChordQuality)>[
  ('m7(b5)', ChordQuality.halfDiminished7),
  ('m7b5', ChordQuality.halfDiminished7),
  ('ø7', ChordQuality.halfDiminished7),
  ('ø', ChordQuality.halfDiminished7),
  ('dim7', ChordQuality.diminished7),
  ('°7', ChordQuality.diminished7),
  ('o7', ChordQuality.diminished7),
  ('dim', ChordQuality.diminished),
  ('°', ChordQuality.diminished),
  ('o', ChordQuality.diminished),
  ('mMaj7', ChordQuality.minorMajor7),
  ('m(maj7)', ChordQuality.minorMajor7),
  ('m7M', ChordQuality.minorMajor7),
  ('mMaj', ChordQuality.minorMajor7),
  ('m(maj)', ChordQuality.minorMajor7),
  ('maj7', ChordQuality.major7),
  ('maj', ChordQuality.major7),
  ('M7', ChordQuality.major7),
  ('Δ7', ChordQuality.major7),
  ('Δ', ChordQuality.major7),
  ('7M', ChordQuality.major7),
  ('7+', ChordQuality.major7),
  ('aug', ChordQuality.augmented),
  ('+', ChordQuality.augmented),
  ('min', ChordQuality.minor),
  ('m7', ChordQuality.minor7),
  ('m6', ChordQuality.minor6),
  ('m', ChordQuality.minor),
  ('-7', ChordQuality.minor7),
  ('-', ChordQuality.minor),
  ('sus2', ChordQuality.sus2),
  ('sus4', ChordQuality.sus4),
  ('7sus4', ChordQuality.dominant7sus4),
  ('7(4)', ChordQuality.dominant7sus4),
  ('4', ChordQuality.sus4),
  ('7', ChordQuality.dominant7),
  ('6', ChordQuality.major6),
  ('5', ChordQuality.power),
  ('', ChordQuality.major),
]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
