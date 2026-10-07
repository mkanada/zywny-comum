// Q07: o teclado com o TRANSPOSE errado (esquecido de ontem, ou não ajustado
// hoje) e o que dizer à pessoa. Dart puro (docs/plano/Q07).
import 'package:meta/meta.dart';

import 'transpose_check.dart' show signedTranspose;

/// Quantas notas erradas seguidas, todas à mesma distância das esperadas e sem
/// nenhuma certa no meio, bastam para dizer que o teclado está deslocado. A
/// ajustar no aceite manual (Q08).
const int kShiftDetectorNotes = 6;

/// A maior distância que o detector considera: uma oitava. Além disso a pessoa
/// está tocando noutro lugar, não com o TRANSPOSE errado.
const int kShiftDetectorMaxDistance = 12;

/// Vê se as últimas [notes] notas erradas têm todas **uma mesma explicação**: o
/// teclado deslocado de `d ≠ 0` semitons (`d = tocada − esperada`, as duas na
/// altura **escrita**). Cada erro traz as distâncias a todas as notas esperadas
/// naquele momento (o acorde do passo, as da janela); `d` vale se está em todas
/// elas. Com uma esperada só é "a mesma distância"; com um acorde, o erro que
/// cai ao lado de outra nota do acorde não desfaz a conta (um teclado em +3
/// tocando Si–Ré–Fá♯ manda Ré–Fá–Lá: o Ré até acerta, o Fá fica a −1 do Fá♯ mas a
/// +3 do Ré, e o Lá a +3 do Fá♯).
///
/// Uma nota certa, nenhuma explicação em comum ou um erro sem esperada por
/// perto zeram a contagem. Dispara **uma vez** por detector.
class ShiftDetector {
  ShiftDetector({this.notes = kShiftDetectorNotes, this.enabled});

  final int notes;

  /// Perguntado a cada nota errada: `false` não conta nada. É o caso do
  /// teclado que não transpõe a saída (o número que chega não muda com o
  /// TRANSPOSE) e do som só do app.
  final bool Function()? enabled;

  Set<int> _candidates = const {};
  int _count = 0;
  bool _fired = false;

  /// Já disparou: não dispara de novo.
  bool get fired => _fired;

  /// Uma nota errada, a cada uma das [distances] das esperadas por perto
  /// (vazio = não havia esperada). Devolve `d` quando esta é a nota que
  /// completa a sequência; havendo mais de um `d` possível, o de menor módulo.
  int? wrong(Iterable<int> distances) {
    if (_fired || !(enabled?.call() ?? true)) return null;
    final now = {
      for (final d in distances)
        if (d != 0 && d.abs() <= kShiftDetectorMaxDistance) d,
    };
    if (now.isEmpty) {
      _reset();
      return null;
    }
    final common = _count == 0 ? now : _candidates.intersection(now);
    if (common.isEmpty) {
      _candidates = now;
      _count = 1;
    } else {
      _candidates = common;
      _count++;
    }
    if (_count < notes) return null;
    _fired = true;
    return (_candidates.toList()..sort(_byModulus)).first;
  }

  static int _byModulus(int a, int b) {
    final c = a.abs().compareTo(b.abs());
    return c != 0 ? c : b.compareTo(a);
  }

  /// Volta a vigiar: começa uma sessão de treino.
  void rearm() {
    _fired = false;
    _reset();
  }

  /// Uma nota certa (ou fora do tempo, mas certa), a cada uma das [distances]
  /// das esperadas por perto: zera a sequência — a menos que o acerto seja só
  /// um acaso do deslocamento. Num acorde, a tecla deslocada pode cair noutra
  /// nota do mesmo acorde (com o teclado em +3, o Ré de Si–Ré–Fá♯ é o Si
  /// deslocado): se algum `d` em curso o explica, ele não conta como acerto.
  void correct([Iterable<int> distances = const []]) {
    if (_candidates.any(distances.contains)) return;
    _reset();
  }

  void _reset() {
    _candidates = const {};
    _count = 0;
  }
}

/// O aviso para a pessoa: o texto e se some ao tocar.
@immutable
class ShiftNotice {
  const ShiftNotice(this.message, {this.hideOnPlay = true});

  final String message;

  /// A faixa some quando a pessoa toca a próxima nota (além dos 8 s).
  final bool hideOnPlay;

  @override
  bool operator ==(Object other) =>
      other is ShiftNotice &&
      other.message == message &&
      other.hideOnPlay == hideOnPlay;

  @override
  int get hashCode => Object.hash(message, hideOnPlay);
}

/// O TRANSPOSE em que o teclado está e o em que deveria estar, a partir da
/// distância [d] vista pelo detector com a música deslocada de [k] semitons.
///
/// [frameShiftsOut]: na medição, o `PitchFrame` já somava `k` à nota recebida
/// (teclado conferido que transpõe a saída). Se não, a distância é o próprio
/// TRANSPOSE do teclado (que o disparo prova que transpõe a saída).
({int current, int wanted}) shiftTransposeOf({
  required int d,
  required int k,
  required bool frameShiftsOut,
}) => (current: frameShiftsOut ? d - k : d, wanted: -k);

/// O texto do detector. Música sem transposição ([k] = 0): fala do
/// deslocamento do teclado; transposta: diz o valor em que o TRANSPOSE está e o
/// que pede.
ShiftNotice shiftNoticeFor({
  required int d,
  required int k,
  required bool frameShiftsOut,
}) {
  final t = shiftTransposeOf(d: d, k: k, frameShiftsOut: frameShiftsOut);
  if (k == 0) {
    return ShiftNotice(
      'Parece que o teclado está transposto em ${signedTranspose(t.current)}. '
      'Ajuste o TRANSPOSE para 0.',
    );
  }
  return ShiftNotice(
    'Parece que o TRANSPOSE está em ${signedTranspose(t.current)}. '
    'Ajuste para ${signedTranspose(t.wanted)}.',
  );
}

/// O disparo do detector, numa música deslocada de [k], **acertou** o TRANSPOSE?
/// Só acontece num teclado ainda não conferido: ele já estava no valor pedido,
/// e o que falta é saber que ele transpõe a saída. Nesse caso não há o que
/// avisar.
bool shiftIsAlreadyRight({
  required int d,
  required int k,
  required bool frameShiftsOut,
}) {
  final t = shiftTransposeOf(d: d, k: k, frameShiftsOut: frameShiftsOut);
  return k != 0 && t.current == t.wanted;
}

/// O texto do lembrete de voltar a 0 (Q07, passo 3).
const String kShiftReminderMessage =
    'Se ajustou o TRANSPOSE para a música anterior, volte para 0.';

/// Devolve `true` se o lembrete vale agora: a música que abriu não é
/// transposta, a anterior era, há teclado e ele **não** transpõe a saída
/// (`false` ou não conferido): com `true` o detector vê o deslocamento de
/// verdade e o app não avisa por suposição.
bool shouldRemindTransposeReset({
  required bool previousWasTransposed,
  required bool nowTransposed,
  required bool hasKeyboard,
  required bool? keyboardShiftsOut,
  required bool appIsSound,
}) =>
    previousWasTransposed &&
    !nowTransposed &&
    hasKeyboard &&
    keyboardShiftsOut != true &&
    !appIsSound;
