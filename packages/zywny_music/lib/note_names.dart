import 'note_name.dart';

/// Como os nomes das notas aparecem na tela (D-LIC-NOMES).
///
/// O arquivo do curso usa sempre a notação científica (`C4`); aqui vai a
/// grafia para humanos. `latin` é o padrão (Dó–Ré–Mi); `letters` é a opção
/// C–D–E das configurações.
enum NoteNaming implements Comparable<NoteNaming> {
  latin('latin'),
  letters('letters');

  const NoteNaming(this.wire);

  /// Como aparece no `SharedPreferences` (`ui_note_naming`).
  final String wire;

  static NoteNaming fromWire(String? wire) {
    for (final value in NoteNaming.values) {
      if (value.wire == wire) return value;
    }
    return NoteNaming.latin;
  }

  @override
  int compareTo(NoteNaming other) => index.compareTo(other.index);
}

const _latinSteps = {
  'C': 'Dó',
  'D': 'Ré',
  'E': 'Mi',
  'F': 'Fá',
  'G': 'Sol',
  'A': 'Lá',
  'B': 'Si',
};

/// Sustenido e bemol musicais (U+266F/U+266D), não `#`/`b` do arquivo.
const String kSharpSign = '♯';
const String kFlatSign = '♭';

/// O nome de [pitch] para a tela: "Dó", "Fá♯", "Si♭4" / "C", "F♯", "B♭4".
///
/// Com [withOctave], o número da oitava vai junto ("Si♭4"). Sem ele (padrão),
/// só a nota e o acidente — é o que o teclado desenhado escreve nas teclas.
String noteLabel(Pitch pitch, NoteNaming naming, {bool withOctave = false}) {
  final base = switch (naming) {
    NoteNaming.latin => _latinSteps[pitch.step]!,
    NoteNaming.letters => pitch.step,
  };
  final alter = switch (pitch.alter) {
    > 0 => kSharpSign,
    < 0 => kFlatSign,
    _ => '',
  };
  final octave = withOctave ? '${pitch.octave}' : '';
  return '$base$alter$octave';
}

/// O nome de um MIDI cru (0–127) para a tela, sem oitava por padrão.
///
/// Fora da faixa do piano o passo é calculado mesmo assim (mod 12); a oitava
/// segue a convenção científica (C4 = 60).
String midiLabel(int midi, NoteNaming naming, {bool withOctave = false}) {
  final pitch = pitchFromMidi(midi);
  return noteLabel(pitch, naming, withOctave: withOctave);
}

/// Um MIDI cru (0–127) como [Pitch]: pretas como sustenido (nunca E# nem B#,
/// como o sorteio do I02); a oitava segue a convenção científica (C4 = 60).
Pitch pitchFromMidi(int midi) {
  const steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  const semis = [0, 2, 4, 5, 7, 9, 11];
  final pc = ((midi % 12) + 12) % 12;
  var step = 'C';
  var alter = 0;
  for (var i = 0; i < steps.length; i++) {
    if (semis[i] == pc) {
      step = steps[i];
      alter = 0;
      break;
    }
    if (semis[i] == (pc - 1 + 12) % 12) {
      // Candidata a sustenido; prefere a forma sustenida à bemol vizinha,
      // como o sorteio do I02 (nunca E#, B#).
      step = steps[i];
      alter = 1;
    }
  }
  // pc pretas caem no ramo acima (C#, D#, F#, G#, A#); E#/B# não existem.
  final octave = (midi ~/ 12) - 1;
  return Pitch(step, alter, octave);
}
