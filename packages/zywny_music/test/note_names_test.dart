// I05, critério 2 — `test/note_names_test.dart`: os 12 sons nas duas grafias,
// com e sem oitava, sustenido e bemol.

import 'package:test/test.dart';
import 'package:zywny_music/note_name.dart';
import 'package:zywny_music/note_names.dart';

void main() {
  group('noteLabel', () {
    test('as sete naturais, sem oitava', () {
      expect(noteLabel(Pitch.parse('C4'), NoteNaming.latin), 'Dó');
      expect(noteLabel(Pitch.parse('D4'), NoteNaming.latin), 'Ré');
      expect(noteLabel(Pitch.parse('E4'), NoteNaming.latin), 'Mi');
      expect(noteLabel(Pitch.parse('F4'), NoteNaming.latin), 'Fá');
      expect(noteLabel(Pitch.parse('G4'), NoteNaming.latin), 'Sol');
      expect(noteLabel(Pitch.parse('A4'), NoteNaming.latin), 'Lá');
      expect(noteLabel(Pitch.parse('B4'), NoteNaming.latin), 'Si');
      expect(noteLabel(Pitch.parse('C4'), NoteNaming.letters), 'C');
      expect(noteLabel(Pitch.parse('D4'), NoteNaming.letters), 'D');
      expect(noteLabel(Pitch.parse('E4'), NoteNaming.letters), 'E');
      expect(noteLabel(Pitch.parse('F4'), NoteNaming.letters), 'F');
      expect(noteLabel(Pitch.parse('G4'), NoteNaming.letters), 'G');
      expect(noteLabel(Pitch.parse('A4'), NoteNaming.letters), 'A');
      expect(noteLabel(Pitch.parse('B4'), NoteNaming.letters), 'B');
    });

    test('os 12 sons de uma oitava nas duas grafias', () {
      const latin = [
        'Dó',
        'Dó♯',
        'Ré',
        'Ré♯',
        'Mi',
        'Fá',
        'Fá♯',
        'Sol',
        'Sol♯',
        'Lá',
        'Lá♯',
        'Si',
      ];
      const letters = [
        'C',
        'C♯',
        'D',
        'D♯',
        'E',
        'F',
        'F♯',
        'G',
        'G♯',
        'A',
        'A♯',
        'B',
      ];
      const steps = [
        'C4',
        'C#4',
        'D4',
        'D#4',
        'E4',
        'F4',
        'F#4',
        'G4',
        'G#4',
        'A4',
        'A#4',
        'B4',
      ];
      for (var i = 0; i < 12; i++) {
        expect(
          noteLabel(Pitch.parse(steps[i]), NoteNaming.latin),
          latin[i],
          reason: steps[i],
        );
        expect(
          noteLabel(Pitch.parse(steps[i]), NoteNaming.letters),
          letters[i],
          reason: steps[i],
        );
      }
    });

    test('sustenido e bemol', () {
      expect(noteLabel(Pitch.parse('F#4'), NoteNaming.latin), 'Fá♯');
      expect(noteLabel(Pitch.parse('F#4'), NoteNaming.letters), 'F♯');
      expect(noteLabel(Pitch.parse('Bb3'), NoteNaming.latin), 'Si♭');
      expect(noteLabel(Pitch.parse('Bb3'), NoteNaming.letters), 'B♭');
      expect(noteLabel(Pitch.parse('Eb4'), NoteNaming.latin), 'Mi♭');
      expect(noteLabel(Pitch.parse('Eb4'), NoteNaming.letters), 'E♭');
    });

    test('com oitava', () {
      expect(
        noteLabel(Pitch.parse('C4'), NoteNaming.latin, withOctave: true),
        'Dó4',
      );
      expect(
        noteLabel(Pitch.parse('C4'), NoteNaming.letters, withOctave: true),
        'C4',
      );
      expect(
        noteLabel(Pitch.parse('F#4'), NoteNaming.latin, withOctave: true),
        'Fá♯4',
      );
      expect(
        noteLabel(Pitch.parse('F#4'), NoteNaming.letters, withOctave: true),
        'F♯4',
      );
      expect(
        noteLabel(Pitch.parse('Bb3'), NoteNaming.latin, withOctave: true),
        'Si♭3',
      );
      expect(
        noteLabel(Pitch.parse('Bb3'), NoteNaming.letters, withOctave: true),
        'B♭3',
      );
    });
  });

  group('pitchFromMidi/midiLabel', () {
    test('C4 = 60, oitava científica', () {
      expect(pitchFromMidi(60), Pitch.parse('C4'));
      expect(midiLabel(60, NoteNaming.latin), 'Dó');
      expect(midiLabel(60, NoteNaming.letters), 'C');
      expect(midiLabel(60, NoteNaming.latin, withOctave: true), 'Dó4');
    });

    test('pretas saem como sustenido', () {
      expect(midiLabel(61, NoteNaming.latin), 'Dó♯');
      expect(midiLabel(61, NoteNaming.letters), 'C♯');
      expect(midiLabel(66, NoteNaming.latin), 'Fá♯');
    });
  });

  group('NoteNaming.fromWire', () {
    test('padrão é latin', () {
      expect(NoteNaming.fromWire(null), NoteNaming.latin);
      expect(NoteNaming.fromWire('latin'), NoteNaming.latin);
      expect(NoteNaming.fromWire('letters'), NoteNaming.letters);
      expect(NoteNaming.fromWire('dó'), NoteNaming.latin);
    });
  });
}
