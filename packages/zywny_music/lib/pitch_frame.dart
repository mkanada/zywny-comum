import 'package:meta/meta.dart';

/// As três alturas de uma música transposta (docs/plano/Q00, "As três
/// alturas") e as quatro conversões entre elas. É o único lugar do app que
/// soma semitom por causa da transposição.
///
/// Com a partitura deslocada de [k] semitons (− = desceu), cada nota tem:
///
///  * **escrita** `w`: a que está na partitura (e no `midi.json`) e a tecla
///    que a pessoa aperta;
///  * **soada** `s = w − k`: a que se ouve, o tom original;
///  * **recebida** `r`: o número que o teclado manda pelo MIDI. Com o
///    TRANSPOSE em −[k], um teclado que transpõe a saída manda `r = s`; um que
///    não transpõe manda `r = w`.
///
/// E o que o app manda ao teclado (M03) é lido por ele de dois jeitos: um
/// teclado que transpõe a entrada soma −[k] ao que recebe, outro não.
///
/// | pergunta | `keyboardShiftsOut` | `keyboardShiftsIn` | resposta |
/// | --- | --- | --- | --- |
/// | escrita da recebida (casador) | sim | — | `r + k` |
/// | | não | — | `r` |
/// | soada da escrita (agendador, motor do app) | — | — | `w − k` |
/// | soada da recebida (monitor) | sim | — | `r` |
/// | | não | — | `r − k` |
/// | a mandar ao teclado, da escrita (M03) | — | sim | `w` |
/// | | — | não | `w − k` |
///
/// Com [appIsSound] o som é do próprio app (o teclado é só controlador, e a
/// pessoa não mexe no TRANSPOSE): nenhum dos dois comportamentos do teclado
/// vale, a recebida é a escrita e ao teclado se manda a soada.
///
/// Com `k = 0` — [PitchFrame.identity], o caminho de sempre — as quatro
/// conversões devolvem o mesmo número, sem custo.
@immutable
class PitchFrame {
  const PitchFrame(
    this.k, {
    this.keyboardShiftsOut = false,
    this.keyboardShiftsIn = false,
    this.appIsSound = false,
  });

  /// Sem transposição: todas as alturas são a mesma.
  static const identity = PitchFrame(0);

  /// Quanto a partitura sobe (+) ou desce (−), em semitons
  /// (`Transposition.semitones`).
  final int k;

  /// O teclado transpõe também o MIDI que **manda** (a recebida é a soada).
  final bool keyboardShiftsOut;

  /// O teclado transpõe também o MIDI que **recebe** do app.
  final bool keyboardShiftsIn;

  /// O som sai do app, não do teclado.
  final bool appIsSound;

  bool get isIdentity => k == 0;

  bool get _out => keyboardShiftsOut && !appIsSound;
  bool get _in => keyboardShiftsIn && !appIsSound;

  /// A altura escrita da nota [received] que chegou do teclado: o que o
  /// casador (`PracticeController`) compara com a partitura.
  int writtenFromReceived(int received) => _out ? received + k : received;

  /// A altura soada da escrita [written]: o que o agendador (K04) e os
  /// motores de som do app tocam.
  int soundingFromWritten(int written) => written - k;

  /// A altura soada da nota [received] do teclado: o que o monitor
  /// (`MidiMonitor`) toca.
  int monitorFromReceived(int received) =>
      soundingFromWritten(writtenFromReceived(received));

  /// O número a mandar ao teclado (M03, `MidiOutSoundEngine`) para a nota de
  /// altura escrita [written] soar no tom original.
  int outFromWritten(int written) => _in ? written : written - k;

  /// O número a mandar ao motor de som para a nota de altura escrita
  /// [written]: o teclado MIDI ([midiKeyboard], M03) lê pela regra dele
  /// ([outFromWritten]); o sintetizador do app toca a soada.
  int engineFromWritten(int written, {required bool midiKeyboard}) =>
      midiKeyboard ? outFromWritten(written) : soundingFromWritten(written);

  /// O mesmo para a nota [received] que chegou do teclado e o monitor (M02)
  /// repassa ao motor.
  int engineFromReceived(int received, {required bool midiKeyboard}) =>
      engineFromWritten(
        writtenFromReceived(received),
        midiKeyboard: midiKeyboard,
      );

  @override
  bool operator ==(Object other) =>
      other is PitchFrame &&
      other.k == k &&
      other.keyboardShiftsOut == keyboardShiftsOut &&
      other.keyboardShiftsIn == keyboardShiftsIn &&
      other.appIsSound == appIsSound;

  @override
  int get hashCode =>
      Object.hash(k, keyboardShiftsOut, keyboardShiftsIn, appIsSound);

  @override
  String toString() =>
      'PitchFrame(k=$k, out=$keyboardShiftsOut, in=$keyboardShiftsIn, '
      'app=$appIsSound)';
}
