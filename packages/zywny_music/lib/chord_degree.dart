import 'package:meta/meta.dart';

import 'chord.dart';

/// Um tom: a tônica (classe de altura e grafia) e se é menor. A grafia da
/// tônica é a que o tom leva na armadura (`G`, `Bb`, `F#`).
@immutable
class KeySpec {
  const KeySpec({
    required this.tonic,
    required this.minor,
    required this.spelling,
  });

  /// Lê `C`, `Bb`, `F#m`, `Am` (a mesma sintaxe do `key:` do formato).
  static KeySpec? parse(String text, {void Function(String)? error}) {
    final match = _keyPattern.firstMatch(
      text.trim().replaceAll('♯', '#').replaceAll('♭', 'b'),
    );
    if (match == null) {
      error?.call(
        '`$text` não é um tom: use uma letra de A a G, com # ou b, '
        'e m para menor (como Bb ou Am).',
      );
      return null;
    }
    final letter = match.group(1)!;
    final accidental = match.group(2)!;
    final alter = accidental == '#' ? 1 : (accidental == 'b' ? -1 : 0);
    return KeySpec(
      tonic: _mod12(_naturals[letter]! + alter),
      minor: match.group(3) != null,
      spelling: letter + accidental,
    );
  }

  /// Classe de altura da tônica, de 0 (Dó) a 11 (Si).
  final int tonic;
  final bool minor;
  final String spelling;

  @override
  bool operator ==(Object other) =>
      other is KeySpec &&
      other.tonic == tonic &&
      other.minor == minor &&
      other.spelling == spelling;

  @override
  int get hashCode => Object.hash(tonic, minor, spelling);

  @override
  String toString() => minor ? '${spelling}m' : spelling;
}

/// Um grau romano, como `ii7`, `V7`, `Imaj7`, `IVm`, `bVII`, `vii°`,
/// `iiø7`, `V7/vi`. Não tem tom: [inKey] o resolve.
@immutable
class ChordDegree {
  const ChordDegree._({
    required this.label,
    required this.numeral,
    required this.shift,
    required this.lower,
    required this.quality,
    this.secondary,
  });

  /// Lê um grau. Devolve `null` e chama [error] se não é um grau.
  static ChordDegree? parse(String text, {void Function(String)? error}) {
    final source = text.trim().replaceAll('♯', '#').replaceAll('♭', 'b');
    final match = _degreePattern.firstMatch(source);
    if (match == null) {
      error?.call(
        '`$text` não é um grau: use algarismos romanos, como ii7, V7, IVm, '
        'bVII ou V7/vi.',
      );
      return null;
    }
    final numeralText = match.group(2)!;
    final shift = switch (match.group(1)) {
      '#' => 1,
      'b' => -1,
      _ => 0,
    };
    // Maiúscula pede acorde maior; minúscula, menor; `m` também pede menor.
    final lower = numeralText == numeralText.toLowerCase();
    final minorThird = lower || match.group(4) != null;
    final seventh = match.group(5);
    final quality = switch (match.group(3)) {
      '°' =>
        seventh == '7' ? ChordQuality.diminished7 : ChordQuality.diminished,
      'ø' => ChordQuality.halfDiminished7,
      '+' => ChordQuality.augmented,
      _ => switch (seventh) {
        '7' => minorThird ? ChordQuality.minor7 : ChordQuality.dominant7,
        'maj7' => minorThird ? ChordQuality.minorMajor7 : ChordQuality.major7,
        '6' => minorThird ? ChordQuality.minor6 : ChordQuality.major6,
        _ => minorThird ? ChordQuality.minor : ChordQuality.major,
      },
    };
    final targetText = match.group(6);
    final secondary = targetText == null ? null : parse(targetText);
    return ChordDegree._(
      label: source,
      numeral: _numerals[numeralText.toLowerCase()]!,
      shift: shift,
      lower: lower,
      quality: quality,
      secondary: secondary,
    );
  }

  /// O texto do grau, sem espaços nas pontas (`V7/vi`).
  final String label;

  /// 1 (I) a 7 (VII).
  final int numeral;

  /// -1 para `b`, 1 para `#`, 0 sem alteração.
  final int shift;

  /// Se o algarismo é minúsculo (`ii`, `vi`).
  final bool lower;
  final ChordQuality quality;

  /// Para `V7/vi`: o grau `vi`, cujo tom é o da dominante secundária.
  final ChordDegree? secondary;

  /// A função do grau no ouvido de casa ou tensão (EX04). `null` quando o grau
  /// não é um dos que essa pergunta usa: só I, iii, vi (casa), ii, IV (afasta-
  /// se), V, V7, vii° e V7/x (tensão), com o acorde que a função pede.
  DegreeFunction? get harmonicFunction {
    final target = secondary;
    if (target != null) {
      return shift == 0 && numeral == 5 && _dominants.contains(quality)
          ? DegreeFunction.tension
          : null;
    }
    if (shift != 0) return null;
    return switch (numeral) {
      1 || 3 || 6 when _stable.contains(quality) => DegreeFunction.rest,
      2 || 4 when _stable.contains(quality) => DegreeFunction.away,
      5 when _dominants.contains(quality) => DegreeFunction.tension,
      7
          when quality == ChordQuality.diminished ||
              quality == ChordQuality.diminished7 =>
        DegreeFunction.tension,
      _ => null,
    };
  }

  /// O acorde deste grau no tom [key]. Com `/x`, o acorde é calculado no
  /// tom do grau `x` (que é o que o `/` diz).
  ChordSymbol inKey(KeySpec key) {
    final target = secondary;
    if (target == null) return _resolve(key);
    final targetChord = target.inKey(key);
    return _resolve(
      KeySpec(
        tonic: targetChord.root,
        minor: target.lower,
        spelling: targetChord.rootSpelling,
      ),
    );
  }

  ChordSymbol _resolve(KeySpec key) {
    final steps = key.minor ? _minorSteps : _majorSteps;
    var pitch = key.tonic + steps[numeral - 1] + shift;
    // Em menor, o VII° é o da harmônica (a sensível), e não o VII natural.
    if (key.minor && numeral == 7 && quality == ChordQuality.diminished) {
      pitch = key.tonic + 11 + shift;
    }
    final root = _mod12(pitch);
    // A letra vem do tom (uma 3ª acima da tônica é sempre outra letra); a
    // alteração é o que sobra entre a nota e a letra natural.
    final letter = (_letters.indexOf(key.spelling[0]) + numeral - 1) % 7;
    var alter = _mod12(root - _naturals[_letters[letter]]!);
    if (alter > 6) alter -= 12;
    final accidental = alter >= 0 ? '#' * alter : 'b' * -alter;
    return ChordSymbol(
      root: root,
      rootSpelling: _letters[letter] + accidental,
      quality: quality,
    );
  }
}

int _mod12(int x) => ((x % 12) + 12) % 12;

const _letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

/// Alturas das notas naturais, de C (0) a B (11).
const _naturals = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

/// Semitons de cada grau nos modos maior e menor natural. Em menor, o V e o
/// VII° vêm da harmônica (`ChordDegree._resolve`).
const _majorSteps = [0, 2, 4, 5, 7, 9, 11];
const _minorSteps = [0, 2, 3, 5, 7, 8, 10];

/// A função de um grau no ouvido de casa ou tensão (EX04): [rest] repousa em
/// casa; [away] afasta-se dela sem pedir volta; [tension] pede resolução.
enum DegreeFunction { rest, away, tension }

/// As qualidades que repousam ou se afastam: tríades e tétrades sem trítono
/// (a dominante não repousa).
const _stable = {
  ChordQuality.major,
  ChordQuality.minor,
  ChordQuality.major7,
  ChordQuality.minorMajor7,
  ChordQuality.minor7,
  ChordQuality.major6,
  ChordQuality.minor6,
};

/// As dominantes (maior e com sétima), que pedem resolução.
const _dominants = {ChordQuality.major, ChordQuality.dominant7};

final _keyPattern = RegExp(r'^([A-G])([#b]?)(m|min)?$');

final _degreePattern = RegExp(
  r'^(#|b)?(VII|VI|V|IV|III|II|I|vii|vi|v|iv|iii|ii|i)(°|ø|\+)?(m)?'
  r'(maj7|7|6)?'
  r'(?:/((?:#|b)?(?:VII|VI|V|IV|III|II|I|vii|vi|v|iv|iii|ii|i)))?$',
);

const _numerals = {
  'i': 1,
  'ii': 2,
  'iii': 3,
  'iv': 4,
  'v': 5,
  'vi': 6,
  'vii': 7,
};
