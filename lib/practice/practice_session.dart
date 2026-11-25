// T01: núcleo do treino, Dart puro — sem UI, sem hardware (M02/M03) e sem
// relógio de parede embutido. Quem chama decide o tempo (`atMs`/`musicalMs`)
// e faz a conversão de segundos de dispositivo para ms musicais (isso é do
// agendador, K04, e do relógio de treino, T02/T03); ver
// docs/plano/T01-casador-de-notas.md.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zywny_audio/performance_track.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import 'chord_demand.dart';
import 'practice_verdict_kind.dart';

export 'practice_verdict_kind.dart';

/// Resultado de uma nota tocada — ou de um evento não tocado, no caso de
/// [PracticeVerdictKind.missed], em que não há nota física correspondente.
@immutable
class NoteVerdict {
  const NoteVerdict({
    this.eventId,
    required this.pitch,
    required this.kind,
    required this.deltaMs,
    this.velocity = 0,
    this.atMs,
  });

  /// Id do [SoundEvent] casado; `null` em [PracticeVerdictKind.wrong] (não
  /// há candidato) e no veredito de um acorde da cifra (AC05), que não é nota
  /// da partitura.
  final String? eventId;
  final int pitch;
  final PracticeVerdictKind kind;

  /// tocada − esperada, em ms: musicais no modo tempo real, de parede desde
  /// a primeira nota do acorde no modo espera. `0` em `wrong`/`missed`.
  final double deltaMs;

  /// Guardada para uso futuro — não avaliada na 1.0 (D-TREINO).
  final int velocity;

  /// O ataque do veredito, em ms musicais, quando não há [eventId] para
  /// dizê-lo: o `onMs` do passo com acorde (AC05), o ataque do acorde no tempo
  /// real (AC05b), ou o instante da tecla errada no tempo real. `null` nos
  /// demais: o compasso sai do evento, ou do passo pendente, como sempre.
  final double? atMs;

  @override
  String toString() =>
      'NoteVerdict($kind pitch=$pitch Δ=${deltaMs.toStringAsFixed(1)}ms'
      '${eventId != null ? " id=$eventId" : ""})';
}

/// Um passo do modo espera: acordes de todas as pautas do aluno com o mesmo
/// `onMs`, fundidos num só. `remaining` é republicado a cada nota certa
/// tocada (mesmo `index`/`onMs`/`notes`), para a UI destacar só o que falta.
///
/// Com [chord] (AC05, tocar pela cifra), o passo também espera o acorde da
/// cifra naquele instante: pode não ter nota de partitura nenhuma (um acorde
/// sozinho), e fecha quando a melodia está tocada **e** o acorde cumpre o que a
/// camada pede.
@immutable
class PracticeStep {
  const PracticeStep({
    required this.index,
    required this.onMs,
    required this.notes,
    required this.remaining,
    this.holdStartMs,
    this.holdEndMs,
    this.holdParkMs,
    this.chord,
  });

  final int index;

  /// Sempre é o `onMs` do passo.
  final double onMs;
  final List<SoundEvent> notes;
  final Set<int> remaining;

  /// A exigência do acorde da cifra neste instante, se há (AC05). Um passo tem
  /// no máximo uma.
  final ChordDemand? chord;

  /// Cápsula do modo "notas com duração" ([WaitModeSession] com
  /// `holdFraction`), em ms musicais: começo e fim, enquanto o aluno segura o
  /// passo. `null` quando ele não está segurando (ou o modo não está ligado).
  final double? holdStartMs;
  final double? holdEndMs;

  /// Onde a música para se o passo não fechar: o fim da nota (a mais curta do
  /// acorde, sem passar do passo seguinte), depois do [holdEndMs]. O freio não
  /// fica no fim da cápsula: o passo só fecha no tique do relógio dela, e a
  /// música parada ali até o tique perdia 0 a 30 ms a cada nota (a deriva se
  /// somava, ~13 ms por nota). `null` junto com o [holdEndMs].
  final double? holdParkMs;
}

/// Soltura cedo no modo "notas com duração": o aluno soltou uma nota certa do
/// passo antes de a cápsula encher. Não é erro (não entra em `hits` nem em
/// `errors`); a sessão só avisa, para quem quiser registrar.
@immutable
class HoldRelease {
  const HoldRelease({
    required this.stepIndex,
    required this.pitch,
    required this.onMs,
    required this.atMs,
    required this.fraction,
  });

  final int stepIndex;
  final int pitch;

  /// `onMs` do passo.
  final double onMs;

  /// Último ponto do relógio musical visto por [WaitModeSession.tick] quando
  /// a nota foi solta.
  final double atMs;

  /// Quanto da cápsula já tinha enchido, de 0 a 1.
  final double fraction;
}

/// Janela de parede, em ms, para as notas de um mesmo acorde no modo
/// espera valerem como "juntas": da primeira à última nota certa do acorde
/// não pode passar disto. Não é `missed` (o modo espera nunca marca falta):
/// se estourar, a tentativa recomeça — as notas ainda seguradas continuam
/// valendo (estão soando junto com o ataque atual), o resto volta a faltar.
const double kWaitChordWindowMs = 300;

/// Quanto da nota o aluno segura no modo "notas com duração" (ND00, decisão 3):
/// 60% da duração (eram 80%; a tolerância subiu porque soltar um pouco antes do
/// fim da nota é o normal de quem toca). Os 40% restantes a música anda sozinha
/// até a nota seguinte, para a cápsula não encher só no último instante.
const double kHoldFraction = 0.6;

/// Modo espera (T01): o tempo não anda até o acorde certo ser tocado.
/// Dirigido só por [noteOn]/[noteOff] — sem relógio interno.
///
/// O acorde fecha quando todas as notas dele estão apertadas juntas e
/// nenhuma tecla errada está apertada: é o estado das teclas que decide, não
/// a ordem. Uma errada no meio não zera a tentativa — soltá-la com o acorde
/// todo seguro fecha o passo. Teclas que já estavam apertadas quando o passo
/// começou (a mão ainda no acorde anterior, no legato) não contam como
/// erradas: só as apertadas durante o passo.
///
/// Com um [PracticeStep.chord] (AC05), o passo também cobra o acorde da cifra:
/// as teclas que ele aceita contam como as notas (sem janela de tempo, só
/// com elas presas), e a tecla que ele não aceita é errada. O passo fecha com a
/// melodia tocada **e** o acorde cumprido; o veredito do acorde sai num só, sem
/// `eventId`, com o `atMs` do ataque. Como as notas, uma tecla já segurada
/// quando o passo começa não conta para o acorde: é preciso soltá-la e
/// apertá-la.
///
/// O estado (BL28) é o passo atual: `state` lê na hora, e a tela escuta o
/// `stream`. Quem é motor (a controladora) liga [onStepChanged], um aviso
/// síncrono, na mesma pilha da mudança.
class WaitModeSession extends Cubit<PracticeStep?> {
  WaitModeSession(
    List<PracticeStep> steps, {
    this._chordWindowMs = kWaitChordWindowMs,
    this.holdFraction,
  }) : _steps = steps,
       super(null) {
    _startStep(0);
  }

  /// Aviso síncrono de cada mudança do [state], sem argumento, como um
  /// `addListener`: chamado logo depois de o estado mudar, na mesma pilha do
  /// motor que o mudou. Não é chamado ao criar a sessão (o passo inicial está em
  /// [state]); quem o liga lê o [state] na hora. Só o motor usa; a tela usa o
  /// [stream].
  VoidCallback? onStepChanged;

  /// Funde os acordes das pautas do aluno pelo mesmo `onMs` (N03 já agrupa
  /// por pauta, com tolerância de [PerformanceTrack.chordToleranceMs]; aqui
  /// só junta pautas diferentes que caem no mesmo instante). Notas de
  /// ornamento (`SoundEvent.ornament`) não entram nos passos — D-TREINO não
  /// cobra ornamento na 1.0, o aluno não precisa tocá-las.
  ///
  /// [chords] (AC05) são as exigências de acorde da rodada: cada uma vai para o
  /// passo da melodia que cai a até [kRangeBoundaryToleranceMs] dela (o Verovio
  /// arredonda os ataques), ou ganha um passo só seu. As que já valem sem
  /// nenhuma tecla ([ChordDemand.satisfied] com vazio) não se cobram e ficam de
  /// fora. Duas no mesmo passo são erro de quem monta a rodada.
  factory WaitModeSession.forStaves(
    PerformanceTrack track, {
    required Set<int> staves,
    double chordWindowMs = kWaitChordWindowMs,
    double? holdFraction,
    List<ChordDemand> chords = const [],
  }) {
    final byOnMs = <double, List<SoundEvent>>{};
    for (final chord in track.chords(staves: staves)) {
      final notes = chord.notes.where((e) => !e.ornament).toList();
      if (notes.isEmpty) continue;
      byOnMs.putIfAbsent(chord.onMs, () => []).addAll(notes);
    }
    final chordAt = _chordsByOnset(chords, byOnMs.keys.toSet());
    for (final onMs in chordAt.keys) {
      byOnMs.putIfAbsent(onMs, () => []);
    }
    final onsets = byOnMs.keys.toList()..sort();
    var i = 0;
    final steps = [
      for (final onMs in onsets)
        PracticeStep(
          index: i++,
          onMs: onMs,
          notes: byOnMs[onMs]!,
          remaining: byOnMs[onMs]!.map((e) => e.pitch).toSet(),
          chord: chordAt[onMs],
        ),
    ];
    return WaitModeSession(
      steps,
      chordWindowMs: chordWindowMs,
      holdFraction: holdFraction,
    );
  }

  /// Onde cada exigência de acorde cai: no instante de uma nota de [onsets] que
  /// está a até [kRangeBoundaryToleranceMs] dela (a mais perto), ou no próprio
  /// ataque. As que já valem sem tecla não entram. [onsets] cresce com os
  /// instantes novos, para que duas exigências próximas caiam no mesmo passo.
  static Map<double, ChordDemand> _chordsByOnset(
    List<ChordDemand> chords,
    Set<double> onsets,
  ) {
    final at = <double, ChordDemand>{};
    for (final chord in chords) {
      if (chord.satisfied(const <int>{})) continue;
      var onMs = chord.onMs;
      var best = double.infinity;
      for (final onset in onsets) {
        final gap = (onset - chord.onMs).abs();
        if (gap <= kRangeBoundaryToleranceMs && gap < best) {
          best = gap;
          onMs = onset;
        }
      }
      if (at.containsKey(onMs)) {
        throw ArgumentError.value(
          chord.onMs,
          'chords',
          'duas exigências de acorde no mesmo passo',
        );
      }
      at[onMs] = chord;
      onsets.add(onMs);
    }
    return at;
  }

  final List<PracticeStep> _steps;

  /// Ver [kWaitChordWindowMs].
  final double _chordWindowMs;

  /// `null`: o passo fecha no aperto, como sempre. Com um valor (ver
  /// [kHoldFraction]), o passo só fecha quando o relógio passa do fim da
  /// cápsula, com as notas ainda presas (ver [tick]).
  final double? holdFraction;

  int _index = 0;
  final Set<int> _held = {};
  Set<int> _remaining = {};
  Set<int> _blocked = {};
  double? _firstHitAtMs;

  /// Fim da cápsula do passo atual enquanto o aluno segura; `null` fora disso.
  double? _holdEndMs;

  /// Último [tick]. Começa em -infinito: sem tique, a cápsula nunca enche (o
  /// relógio ainda não andou).
  double _lastTickMs = double.negativeInfinity;

  /// Notas certas do acorde pendente, ainda sem veredito: o `correct` só
  /// sai quando o acorde fecha, todas juntas — antes disso a UI continua
  /// mostrando o acorde inteiro como esperado.
  final Map<int, ({double atMs, int velocity})> _hits = {};

  /// Teclas erradas apertadas durante o passo e ainda seguradas: enquanto
  /// houver alguma, o acorde não fecha.
  final Set<int> _wrongHeld = {};

  /// As teclas que o passo aceitou e que o aluno segura agora, com o instante
  /// em que foram apertadas: as notas da melodia e as do acorde (AC05). Só
  /// entram as apertadas depois de o passo começar ([_startStep] limpa).
  final Map<int, double> _chordHeld = {};

  /// Publica o passo atual (o [state]). Como o `ValueNotifier` de antes, um valor
  /// igual ao anterior não avisa (só `null` sobre `null`, ao acabar a peça de novo).
  /// Um passo novo avisa sempre, mesmo com os mesmos campos: [PracticeStep] não tem
  /// `==` de valor, e a controladora repinta a cada publicação. O aviso do motor
  /// ([onStepChanged]) vem logo depois do `emit`. Depois do `close`, não há o que
  /// avisar.
  void _setStep(PracticeStep? next) {
    if (isClosed || next == state) return;
    emit(next);
    onStepChanged?.call();
  }

  final StreamController<NoteVerdict> _verdicts =
      StreamController<NoteVerdict>.broadcast(sync: true);

  /// `sync: true`: emissão é uma decisão pura e imediata de [noteOn]/
  /// [noteOff], sem I/O — o padrão assíncrono só obrigaria os testes a
  /// aguardar uma volta de event loop por chamada sem trazer benefício.
  Stream<NoteVerdict> get verdicts => _verdicts.stream;

  final StreamController<HoldRelease> _releases =
      StreamController<HoldRelease>.broadcast(sync: true);

  /// Solturas cedo da cápsula (só com [holdFraction]). Não é veredito: a nota
  /// volta a faltar e nada é contado.
  Stream<HoldRelease> get releases => _releases.stream;

  bool get done => _index >= _steps.length;

  /// Relógio musical, para o modo "notas com duração": quem chama passa o
  /// tempo musical atual. Sem [holdFraction] não faz nada.
  ///
  /// Com a cápsula armada (todas as notas do passo presas, nenhuma errada) e
  /// `musicalMs` além do fim dela, o passo fecha. Guarda o tempo para que um
  /// aperto que chegue depois do fim feche na hora.
  void tick(double musicalMs) {
    _lastTickMs = musicalMs;
    if (done || _holdEndMs == null) return;
    if (_stepReady() && musicalMs >= _holdEndMs!) {
      _completeStep();
    }
  }

  /// Nota física apertada. `atMs` é o relógio de parede do app (mesma
  /// unidade em todas as chamadas de uma sessão) — usado só para o
  /// `deltaMs` do veredito, nunca para decidir se o passo avança.
  void noteOn(int pitch, {required double atMs, int velocity = 0}) {
    if (done) {
      _held.add(pitch);
      return;
    }

    if (_blocked.contains(pitch)) {
      // Ainda presa desde antes deste passo (nota repetida): exige soltar e
      // apertar de novo.
      _held.add(pitch);
      return;
    }

    if (_firstHitAtMs != null && atMs - _firstHitAtMs! > _chordWindowMs) {
      // Fora da janela de simultaneidade: a tentativa recomeça. Qualquer
      // ataque vale, certo ou errado — o errado só emite o veredito e não
      // abre janela nova.
      _restartChord();
      if (done) return;
    }
    _held.add(pitch);

    final step = _steps[_index];
    if (!_remaining.contains(pitch)) {
      // Nota que já vale no acorde (repetida sem soltar) não é erro. Com acorde
      // da cifra, ela também conta para ele.
      if (step.notes.any((e) => e.pitch == pitch)) {
        _chordHeld[pitch] = atMs;
        if (step.chord != null) _completeOrPublish();
        return;
      }
      // Tecla do acorde da cifra (AC05): conta para ele, e não é erro.
      if (step.chord?.allows(pitch) ?? false) {
        _chordHeld[pitch] = atMs;
        _completeOrPublish();
        return;
      }
      // Errada: o acorde não fecha enquanto ela estiver apertada. As certas
      // já seguradas continuam valendo. Num passo com acorde, o veredito leva o
      // ataque dele, para o compasso sair certo na escada.
      _wrongHeld.add(pitch);
      _verdicts.add(
        NoteVerdict(
          pitch: pitch,
          kind: PracticeVerdictKind.wrong,
          deltaMs: 0,
          velocity: velocity,
          atMs: step.chord == null ? null : step.onMs,
        ),
      );
      return;
    }

    _firstHitAtMs ??= atMs;
    _remaining.remove(pitch);
    _hits[pitch] = (atMs: atMs, velocity: velocity);
    _chordHeld[pitch] = atMs;
    _completeOrPublish();
  }

  /// O passo pode fechar: as notas da melodia estão todas tocadas, nenhuma
  /// tecla errada está segura, e o acorde da cifra (se há) cumpre o que a camada
  /// pede.
  bool _stepReady() {
    if (_remaining.isNotEmpty || _wrongHeld.isNotEmpty) return false;
    final step = _steps[_index];
    final chord = step.chord;
    return chord == null || chord.satisfied(_chordKeysOf(step));
  }

  /// As teclas que o acorde do [step] vê: as que o passo aceitou e o aluno segura,
  /// menos as notas da melodia que o acorde não aceita (a nota de passagem não é
  /// do acorde, e a melodia já se cobra pelos ids).
  Set<int> _chordKeysOf(PracticeStep step) {
    final chord = step.chord;
    if (chord == null) return const <int>{};
    final melody = {for (final e in step.notes) e.pitch};
    return {
      for (final pitch in _chordHeld.keys)
        if (!melody.contains(pitch) || chord.allows(pitch)) pitch,
    };
  }

  /// Fecha o passo se ele pode fechar ([_stepReady]); senão republica o que falta.
  void _completeOrPublish() {
    if (_stepReady()) {
      if (holdFraction == null) {
        _completeStep();
        return;
      }
      _holdEndMs ??= _holdEndOf(_index);
      final holdEnd = _holdEndMs;
      // Sem duração, ou a música já passou do fim da cápsula antes do aperto
      // (o `tick` já andou): fecha na hora.
      if (holdEnd == null || _lastTickMs >= holdEnd) {
        _completeStep();
        return;
      }
    }
    _publish(_steps[_index]);
  }

  /// Fim da cápsula do passo [index]: [kHoldFraction] da duração, contada da
  /// nota mais curta do acorde e sem passar do começo do passo seguinte (a
  /// nota longa que continua presa depois disso não é cobrada). `null` se a
  /// nota não tem duração.
  double? _holdEndOf(int index) {
    final end = _noteEndOf(index);
    if (end == null) return null;
    return _steps[index].onMs + holdFraction! * (end - _steps[index].onMs);
  }

  /// Fim da nota do passo [index]: o da nota mais curta do acorde, sem passar do
  /// começo do passo seguinte. `null` se a nota não tem duração.
  double? _noteEndOf(int index) {
    final step = _steps[index];
    if (step.notes.isEmpty) return null;
    var end = step.notes.first.offMs;
    for (final note in step.notes) {
      if (note.offMs < end) end = note.offMs;
    }
    if (index + 1 < _steps.length && _steps[index + 1].onMs < end) {
      end = _steps[index + 1].onMs;
    }
    return end <= step.onMs ? null : end;
  }

  /// O acorde fechou: um `correct` por nota, todos de uma vez, e o passo
  /// seguinte. `deltaMs` conta da primeira nota do acorde.
  void _completeStep() {
    final step = _steps[_index];
    final first = _hits.values.isEmpty
        ? 0.0
        : _hits.values.map((h) => h.atMs).reduce((a, b) => a < b ? a : b);
    for (final pitch in step.notes.map((e) => e.pitch).toSet()) {
      final hit = _hits[pitch];
      _verdicts.add(
        NoteVerdict(
          eventId: step.notes.firstWhere((e) => e.pitch == pitch).id,
          pitch: pitch,
          kind: PracticeVerdictKind.correct,
          deltaMs: hit == null ? 0 : hit.atMs - first,
          velocity: hit?.velocity ?? 0,
        ),
      );
    }
    if (step.chord != null) _emitChordVerdict(step, first);
    _startStep(_index + 1);
  }

  /// O acorde do [step] fechou: um `correct` só, sem `eventId` (o acorde não é
  /// nota da partitura), com o `atMs` do ataque. A tecla é a mais grave das que
  /// cumpriram o acorde. `deltaMs` é a da primeira delas contra a primeira da
  /// melodia ([melodyFirst]); sem melodia no passo, é 0.
  void _emitChordVerdict(PracticeStep step, double melodyFirst) {
    final keys = _chordKeysOf(step).toList()..sort();
    final chordFirst = keys.isEmpty
        ? 0.0
        : keys.map((p) => _chordHeld[p]!).reduce((a, b) => a < b ? a : b);
    _verdicts.add(
      NoteVerdict(
        pitch: keys.isEmpty ? 0 : keys.first,
        kind: PracticeVerdictKind.correct,
        deltaMs: _hits.isEmpty ? 0 : chordFirst - melodyFirst,
        atMs: step.onMs,
      ),
    );
  }

  /// Tecla solta: limpa o bloqueio de "precisa soltar e apertar de novo"
  /// para essa tecla. Soltar uma nota certa antes de o acorde fechar a faz
  /// faltar de novo: o acorde só vale com todas as notas juntas. Soltar a
  /// última errada com o acorde todo apertado fecha o passo.
  void noteOff(int pitch) {
    _held.remove(pitch);
    _blocked.remove(pitch);
    _chordHeld.remove(pitch);
    final wasWrong = _wrongHeld.remove(pitch);
    if (done) return;
    if (wasWrong) {
      // Com a cápsula, a errada solta pode deixar o acorde pronto mas ainda sem
      // fim: `_completeOrPublish` então republica a cápsula em vez de fechar.
      if (_stepReady()) _completeOrPublish();
      return;
    }
    final step = _steps[_index];
    if (!_remaining.contains(pitch) &&
        step.notes.any((e) => e.pitch == pitch)) {
      // Soltar uma nota certa com a cápsula armada é soltura cedo: a nota volta
      // a faltar, e o aluno não é penalizado (ND00, decisão 6).
      final holdEnd = _holdEndMs;
      if (holdEnd != null) {
        final span = holdEnd - step.onMs;
        _releases.add(
          HoldRelease(
            stepIndex: step.index,
            pitch: pitch,
            onMs: step.onMs,
            atMs: _lastTickMs,
            fraction: ((_lastTickMs - step.onMs) / span)
                .clamp(0.0, 1.0)
                .toDouble(),
          ),
        );
        _holdEndMs = null;
      }
      _remaining.add(pitch);
      _hits.remove(pitch);
      if (_remaining.length == step.notes.map((e) => e.pitch).toSet().length) {
        _firstHitAtMs = null;
      }
      _publish(step);
    }
  }

  /// T04 (loop A-B): reinicia no primeiro passo a partir de `onMs`.
  void resetTo(double onMs) {
    // O começo do trecho vem arredondado (a barra do compasso, em ms inteiros);
    // o ataque um pouco antes dele ainda é do trecho (como no `rangeView`).
    final index = _steps.indexWhere(
      (s) => s.onMs >= onMs - kRangeBoundaryToleranceMs,
    );
    // A posição voltou: o relógio que vale é o do próximo tique.
    _lastTickMs = double.negativeInfinity;
    _startStep(index == -1 ? _steps.length : index);
  }

  void _startStep(int index) {
    _index = index;
    _holdEndMs = null;
    if (done) {
      _remaining = {};
      _blocked = {};
      _setStep(null);
      return;
    }
    final step = _steps[index];
    _remaining = step.notes.map((e) => e.pitch).toSet();
    _blocked = _held.intersection(_remaining);
    _hits.clear();
    // O que ainda está apertado de antes não é erro deste passo, e não conta para
    // o acorde dele (só o apertado depois de o passo começar).
    _wrongHeld.clear();
    _chordHeld.clear();
    _firstHitAtMs = null;
    _publish(step);
  }

  /// Recomeça a tentativa do acorde atual (janela de simultaneidade
  /// estourada): as notas ainda seguradas continuam valendo — estão soando
  /// junto com o ataque que disparou o recomeço — e o resto volta a faltar.
  /// O ataque atual ainda não está em [_held] aqui: se for nota do passo,
  /// cai em [_remaining] e o fluxo normal o conta como primeiro da nova
  /// tentativa; se for errada, só emite o veredito. Pode concluir o passo
  /// (tudo segurado, nenhuma errada) e avançar. Tecla ainda presa desde o
  /// passo anterior ([_blocked]) continua faltando: precisa ser solta e
  /// apertada de novo.
  void _restartChord() {
    final step = _steps[_index];
    _remaining = step.notes
        .map((e) => e.pitch)
        .toSet()
        .difference(_held.difference(_blocked));
    _hits.removeWhere((pitch, _) => !_held.contains(pitch));
    _firstHitAtMs = null;
    // A cápsula é recalculada (o mesmo valor) por `_completeOrPublish`.
    _holdEndMs = null;
    _completeOrPublish();
  }

  void _publish(PracticeStep step) {
    final holdEnd = _holdEndMs;
    _setStep(
      PracticeStep(
        index: step.index,
        onMs: step.onMs,
        notes: step.notes,
        remaining: Set.of(_remaining),
        holdStartMs: holdEnd == null ? null : step.onMs,
        holdEndMs: holdEnd,
        holdParkMs: holdEnd == null ? null : _noteEndOf(_index),
        chord: step.chord,
      ),
    );
  }

  @override
  Future<void> close() {
    unawaited(_verdicts.close());
    unawaited(_releases.close());
    return super.close();
  }
}

/// Modo tempo real (T01): casa notas tocadas — já convertidas para ms
/// musicais pela camada de cima (K04) — contra a janela de cada evento
/// esperado. Dirigido por [noteOn] e por [tick] (que marca `missed`).
///
/// Com [chords] (AC05b, tocar pela cifra), cada exigência de acorde tem uma
/// janela `[onMs − early, onMs + late]` com a mesma tolerância das notas. As
/// teclas que ela aceita e que são apertadas dentro da janela contam para ela
/// (sem ordem nem soltura: a janela é a simultaneidade). Ao fim da janela, o
/// acorde vira `correct`, `early` ou `late` (pelo primeiro toque, como as
/// notas) se essas teclas cumprem o acorde, ou `missed` se não. Sem `eventId`
/// e com o `atMs` do ataque. Uma tecla já presa desde o ataque anterior não
/// conta para o seguinte: é preciso apertá-la de novo dentro da janela.
class RealtimeSession {
  RealtimeSession(
    List<SoundEvent> events, {
    required this.speed,
    this.windowOkMs = 75,
    this.windowMaxMs = 150,
    this.adaptiveWindow = false,
    this.forgiveSounding = false,
    List<SoundEvent> appNotes = const [],
    List<ChordDemand> chords = const [],
  }) : _all = List<SoundEvent>.of(events)
         ..sort((a, b) => a.onMs.compareTo(b.onMs)),
       _appNotes = List<SoundEvent>.of(appNotes) {
    _pending = List<SoundEvent>.of(_all);
    _chordsAll = _attacksOf(chords);
    _chords = [for (final chord in _chordsAll) chord.fresh()];
    if (adaptiveWindow) _computeWindows();
    _computeGroups();
  }

  /// Só os eventos das pautas do aluno entram na avaliação — o resto é
  /// tocado pelo app (T02) e não conta.
  factory RealtimeSession.forStaves(
    PerformanceTrack track, {
    required Set<int> staves,
    required double speed,
    double windowOkMs = 75,
    double windowMaxMs = 150,
    bool adaptiveWindow = false,
    bool forgiveSounding = false,
    bool absorbAppNotes = false,
    List<ChordDemand> chords = const [],
  }) {
    final events = track.events.where((e) => staves.contains(e.staff));
    return RealtimeSession(
      events.toList(),
      speed: speed,
      windowOkMs: windowOkMs,
      windowMaxMs: windowMaxMs,
      adaptiveWindow: adaptiveWindow,
      forgiveSounding: forgiveSounding,
      // As notas do app de toda a peça, e não só das pautas do aluno: a do app
      // costuma estar na pauta que o aluno não toca.
      appNotes: absorbAppNotes
          ? [
              for (final e in track.events)
                if (e.byApp) e,
            ]
          : const [],
      chords: chords,
    );
  }

  final double speed;
  final double windowOkMs;
  final double windowMaxMs;

  /// T10, para passagens rápidas (desligada: as janelas são as fixas). A
  /// janela de cada evento encolhe com o vizinho de mesmo pitch na mesma
  /// pauta: antes da nota, vai até `min(windowMaxMs, metade do intervalo
  /// até o anterior)`; depois, até `min(windowMaxMs, 3/4 do intervalo até o
  /// seguinte)` — quem lê se atrasa mais do que se adianta. A de certo é
  /// `min(windowOkMs, metade do menor intervalo)`. A nota tocada casa com o
  /// pendente **mais antigo** de mesmo pitch cuja janela a contém (nunca
  /// pula um pendente para casar com o seguinte), e o evento cuja janela já
  /// fechou antes dela vira `missed` na hora (não espera o [tick]).
  final bool adaptiveWindow;

  /// T10: a nota a mais (sem evento para casar) da altura de uma nota que
  /// soa naquele instante não vira `wrong` — é o dedo que roçou uma nota do
  /// acorde, a nota repetida do trilo, ou a tocada tarde demais, que já
  /// contou como `missed`. "Soa" vale do começo da nota (menos a janela de
  /// certo) ao fim dela, e no ornamento, do começo ao fim do ornamento todo.
  final bool forgiveSounding;

  final List<SoundEvent> _all;
  late List<SoundEvent> _pending;

  /// As notas do app (`byApp`, não cobradas) da peça, que absorvem um toque cada
  /// quando ficam **fora da janela** do [resetTo] (antes do começo, com a
  /// tolerância, ou a partir do fim): a volta na hora (LP25) decide o compasso, e
  /// a nota do app da folga da barra já saiu da janela, mas o aluno que toca junto
  /// ainda a acerta. Vazia, nada muda (ver [forStaves]).
  final List<SoundEvent> _appNotes;

  /// A última tecla de [noteOn] foi absorvida por uma nota do app fora da janela
  /// (não é do aluno: o controlador não a conta na escuta do erro).
  bool lastNoteAbsorbed = false;

  /// As notas de [_appNotes] fora da janela atual, que ainda absorvem um toque; cada
  /// uma absorve no máximo um, e sai da lista ([_absorbApp]).
  List<SoundEvent> _absorbers = const [];

  /// Os ataques de cifra (AC05b) da sessão, na ordem de `onMs`, com a janela de
  /// cada um; e os que ainda estão abertos (sem veredito), com as teclas que
  /// contam para eles. [resetTo] refaz os abertos a partir dos de [_chordsAll].
  late final List<_ChordAttack> _chordsAll;
  late List<_ChordAttack> _chords;

  /// O ataque do primeiro alvo ainda pendente (o mais cedo, nota ou acorde), ou
  /// `null`.
  double? get firstPendingOnMs {
    final note = _pending.isEmpty ? null : _pending.first.onMs;
    final chord = _chords.isEmpty ? null : _chords.first.onMs;
    if (note == null) return chord;
    if (chord == null) return note;
    return note < chord ? note : chord;
  }

  /// As notas depois do fim do trecho ([resetTo] com `untilMs`).
  List<SoundEvent> _beyond = const [];

  /// Os ataques de cifra depois do fim do trecho (como [_beyond]): a tecla deles
  /// tocada um pouco antes do fim não é `wrong` do compasso que repete.
  List<_ChordAttack> _beyondChords = const [];

  /// T11, a *fioritura*: um grupo irregular longo ([SoundEvent.groupId], 3
  /// eventos ou mais) tem a primeira e a última notas com a janela normal; as
  /// de dentro valem **na ordem**, com a janela do começo ao fim do grupo (a
  /// de [windowMaxMs] antes da primeira até [windowMaxMs] depois da última),
  /// porque o ritmo do grupo é livre: o que importa é ler as notas certas na
  /// ordem e chegar na seguinte. Uma nota que casa com uma de dentro adiante de
  /// outra ainda pendente deixa a(s) de trás `missed`; a de trás, tocada depois,
  /// já não tem para onde ir e vira `wrong`.
  final Map<SoundEvent, _Fioritura> _inner = Map.identity();

  void _computeGroups() {
    final groups = <int, List<SoundEvent>>{};
    for (final e in _all) {
      final id = e.groupId;
      if (id != null && !e.ornament) groups.putIfAbsent(id, () => []).add(e);
    }
    for (final group in groups.values) {
      if (group.length < 3) continue;
      final fioritura = _Fioritura(
        startMs: group.first.onMs - windowMaxMs,
        endMs: group.last.onMs + windowMaxMs,
      );
      for (var i = 1; i < group.length - 1; i++) {
        fioritura.order.add(group[i]);
        _inner[group[i]] = fioritura;
      }
    }
  }

  /// Com [adaptiveWindow], as janelas de cada evento (por identidade: as
  /// notas de um ornamento repetem o id): antes, depois e a de certo.
  final Map<SoundEvent, ({double early, double late, double ok})> _windowOf =
      Map.identity();

  /// Com [forgiveSounding], o trecho de cada ornamento (id → começo e fim
  /// das notas dele).
  Map<String, ({double onMs, double offMs})>? _ornamentSpans;

  void _computeWindows() {
    final groups = <(int, int), List<SoundEvent>>{};
    for (final e in _all) {
      groups.putIfAbsent((e.staff, e.pitch), () => []).add(e);
    }
    for (final group in groups.values) {
      for (var i = 0; i < group.length; i++) {
        final e = group[i];
        // Vizinhos no mesmo instante (a mesma tecla em duas vozes) não
        // encolhem a janela: o mais antigo casa primeiro.
        double? before, after;
        for (var j = i - 1; j >= 0 && before == null; j--) {
          final gap = e.onMs - group[j].onMs;
          if (gap > 0) before = gap;
        }
        for (var j = i + 1; j < group.length && after == null; j++) {
          final gap = group[j].onMs - e.onMs;
          if (gap > 0) after = gap;
        }
        final ok = _capGap(before, 0.5, _capGap(after, 0.5, windowOkMs));
        _windowOf[e] = (
          early: _capGap(before, 0.5, windowMaxMs),
          late: _capGap(after, 0.75, windowMaxMs),
          ok: ok,
        );
      }
    }
  }

  /// Os ataques de cifra da sessão (AC05b), na ordem de `onMs`. Um que já vale
  /// sem tecla (o N.C.) não se cobra e fica de fora. Sem [adaptiveWindow], todos
  /// têm a janela fixa das notas; com ela, o vizinho mais perto (outro ataque
  /// de cifra) encolhe a janela, como as notas de mesmo tom.
  List<_ChordAttack> _attacksOf(List<ChordDemand> chords) {
    final demands = [
      for (final chord in chords)
        if (!chord.satisfied(const <int>{})) chord,
    ]..sort((a, b) => a.onMs.compareTo(b.onMs));
    return [
      for (var i = 0; i < demands.length; i++) _chordAttackAt(demands, i),
    ];
  }

  _ChordAttack _chordAttackAt(List<ChordDemand> demands, int i) {
    final onMs = demands[i].onMs;
    double? before, after;
    for (var j = i - 1; j >= 0 && before == null; j--) {
      final gap = onMs - demands[j].onMs;
      if (gap > 0) before = gap;
    }
    for (var j = i + 1; j < demands.length && after == null; j++) {
      final gap = demands[j].onMs - onMs;
      if (gap > 0) after = gap;
    }
    if (!adaptiveWindow) {
      return _ChordAttack(
        demands[i],
        early: windowMaxMs,
        late: windowMaxMs,
        ok: windowOkMs,
      );
    }
    return _ChordAttack(
      demands[i],
      early: _capGap(before, 0.5, windowMaxMs),
      late: _capGap(after, 0.75, windowMaxMs),
      ok: _capGap(before, 0.5, _capGap(after, 0.5, windowOkMs)),
    );
  }

  final StreamController<NoteVerdict> _verdicts =
      StreamController<NoteVerdict>.broadcast(sync: true);
  Stream<NoteVerdict> get verdicts => _verdicts.stream;

  /// As janelas valem no andamento original e ficam em ms musicais: o rigor
  /// acompanha o andamento — a `speed` 0.5 os 75 ms viram 150 ms de parede
  /// (metade do andamento, metade do rigor).
  double get _okMs => windowOkMs;
  double get _maxMs => windowMaxMs;

  /// [delta] (tocada − esperada) cabe na janela de [e]: a fixa, ou a de
  /// [adaptiveWindow].
  bool _inWindow(SoundEvent e, double delta) {
    final w = _windowOf[e];
    if (w == null) return delta.abs() <= _maxMs;
    return delta < 0 ? -delta <= w.early : delta <= w.late;
  }

  /// O fim da janela de [e], em ms musicais.
  double _windowEnd(SoundEvent e) =>
      _inner[e]?.endMs ?? e.onMs + (_windowOf[e]?.late ?? _maxMs);

  /// A janela de certo de [e].
  double _okFor(SoundEvent e) => _windowOf[e]?.ok ?? _okMs;

  /// Nota tocada, já em ms musicais. Casa com o evento pendente de mesmo
  /// pitch mais próximo dentro de [_maxMs] (com [adaptiveWindow], o mais
  /// antigo cuja janela contém a nota). Ornamentos entram como candidatos
  /// só para a nota tocada não virar `wrong`: se casarem, são consumidos sem
  /// veredito (D-TREINO: não cobrados na 1.0).
  void noteOn(int pitch, double musicalMs, {int velocity = 0}) {
    lastNoteAbsorbed = false;
    if (adaptiveWindow) _expire(musicalMs, pitch: pitch);
    // Os ataques de cifra que já fecharam decidem antes desta tecla (ela não é
    // mais deles). Depois, a tecla conta para os que a janela dela cobre; ela
    // pode ser também a nota da melodia (a de cima do hino), e conta para as duas.
    _expireChords(musicalMs);
    final chordKey = _pressChord(pitch, musicalMs);
    final found = _candidates(pitch, musicalMs);
    final best = found.best;
    if (best != null) {
      final inner = _inner[best];
      if (inner != null) _skipBefore(best, inner);
      _pending.remove(best);
      final delta = found.bestDelta!;
      final kind = inner != null || delta.abs() <= _okFor(best)
          ? PracticeVerdictKind.correct
          : (delta < 0 ? PracticeVerdictKind.early : PracticeVerdictKind.late);
      _verdicts.add(
        NoteVerdict(
          eventId: best.id,
          pitch: pitch,
          kind: kind,
          deltaMs: delta,
          velocity: velocity,
        ),
      );
      return;
    }

    final ornament = found.ornament;
    if (ornament != null) {
      _pending.remove(ornament);
      return;
    }

    // A tecla não é erro deste compasso se for de outra coisa ([_belongsElsewhere]).
    if (_belongsElsewhere(pitch, musicalMs, chordKey)) return;

    if (forgiveSounding && _sounding(pitch, musicalMs)) return;

    _verdicts.add(
      NoteVerdict(
        pitch: pitch,
        kind: PracticeVerdictKind.wrong,
        deltaMs: 0,
        velocity: velocity,
        atMs: musicalMs,
      ),
    );
  }

  /// A tecla [pitch], tocada em [musicalMs], é de outra coisa e não vira `wrong`
  /// deste compasso. Na ordem: o acorde da cifra que a janela aberta aceita
  /// ([chordKey], já apurado em [noteOn]; o veredito do acorde sai no fim da
  /// janela); a nota do app fora da janela ([_absorbApp]), que é de quem toca junto
  /// com o app; a primeira nota do compasso seguinte, tocada um pouco antes do fim
  /// do trecho ([resetTo] com `untilMs`); e o acorde do compasso seguinte. Fica
  /// fora de [noteOn] só para caber no limite de linhas do `dart_code_linter`; a
  /// ordem é a mesma, e [_absorbApp] só gasta a nota do app se as anteriores não
  /// casaram.
  bool _belongsElsewhere(int pitch, double musicalMs, bool chordKey) {
    if (chordKey) return true;
    // Nota do app fora da janela ([_appNotes]): a tecla que casa com ela é de
    // quem toca junto com o app, não erro deste compasso.
    if (_absorbApp(pitch, musicalMs)) return true;
    for (final e in _beyond) {
      if (e.pitch == pitch &&
          !e.ornament &&
          musicalMs >= e.onMs - _maxMs &&
          musicalMs <= e.onMs + _maxMs) {
        return true;
      }
    }
    // O mesmo para o acorde do compasso seguinte.
    return _beyondChordKey(pitch, musicalMs);
  }

  /// [t] cai na janela de [a] (a de [_inWindow] para as notas, com a do ataque).
  bool _inChordWindow(_ChordAttack a, double t) {
    final delta = t - a.onMs;
    return delta < 0 ? -delta <= a.early : delta <= a.late;
  }

  /// A tecla [pitch], apertada em [musicalMs], conta para cada ataque de cifra
  /// aberto (a janela dele cobre o instante) que a aceita. Só conta a apertada
  /// dentro da janela: a que chegou antes dela é errada, e a que ficou presa
  /// desde o ataque anterior precisa ser solta e apertada de novo. `true` se
  /// algum ataque a aceitou.
  bool _pressChord(int pitch, double musicalMs) {
    var accepted = false;
    for (final a in _chords) {
      if (!_inChordWindow(a, musicalMs) || !a.demand.allows(pitch)) continue;
      accepted = true;
      a.pressed.putIfAbsent(pitch, () => musicalMs);
    }
    return accepted;
  }

  /// Uma nota do app de altura [pitch] fora da janela ([_absorbers]) que a tecla
  /// casa em [_maxMs]: absorve a tecla e sai da lista. `true` se absorveu.
  bool _absorbApp(int pitch, double musicalMs) {
    for (var i = 0; i < _absorbers.length; i++) {
      final e = _absorbers[i];
      if (e.pitch == pitch && (musicalMs - e.onMs).abs() <= _maxMs) {
        _absorbers.removeAt(i);
        lastNoteAbsorbed = true;
        return true;
      }
    }
    return false;
  }

  /// A tecla [pitch] é de um acorde do compasso seguinte ([_beyondChords]) e
  /// foi tocada perto dele: não é `wrong` deste compasso.
  bool _beyondChordKey(int pitch, double musicalMs) => _beyondChords.any(
    (a) =>
        a.demand.allows(pitch) &&
        musicalMs >= a.onMs - _maxMs &&
        musicalMs <= a.onMs + _maxMs,
  );

  /// Decide os ataques de cifra cuja janela já fechou em [now] (ver
  /// [_decideChord]).
  void _expireChords(double now) {
    _chords.removeWhere((a) {
      if (now <= a.endMs) return false;
      _decideChord(a);
      return true;
    });
  }

  /// O ataque de cifra [a] fechou. `correct`, `early` ou `late` (pelo primeiro
  /// toque das teclas que contam, como as notas) se essas teclas cumprem o
  /// acorde; senão `missed`. Não tem `eventId` (o acorde não é nota da partitura),
  /// e leva o ataque em `atMs`, para o compasso sair dele e não do último toque.
  void _decideChord(_ChordAttack a) {
    final keys = a.pressed;
    if (keys.isEmpty || !a.demand.satisfied(keys.keys.toSet())) {
      _verdicts.add(
        NoteVerdict(
          pitch: 0,
          kind: PracticeVerdictKind.missed,
          deltaMs: 0,
          atMs: a.onMs,
        ),
      );
      return;
    }
    final first = keys.values.reduce((x, y) => x < y ? x : y);
    final delta = first - a.onMs;
    final kind = delta.abs() <= a.ok
        ? PracticeVerdictKind.correct
        : (delta < 0 ? PracticeVerdictKind.early : PracticeVerdictKind.late);
    _verdicts.add(
      NoteVerdict(
        pitch: keys.keys.reduce((x, y) => x < y ? x : y),
        kind: kind,
        deltaMs: delta,
        atMs: a.onMs,
      ),
    );
  }

  /// O que a nota tocada em [pitch] casa entre os pendentes: a nota de melhor
  /// alinhamento ([best], com o [bestDelta]) e, se nenhuma serve, o ornamento
  /// mais próximo ([ornament]).
  ({SoundEvent? best, double? bestDelta, SoundEvent? ornament}) _candidates(
    int pitch,
    double musicalMs,
  ) {
    SoundEvent? best;
    double? bestDelta;
    SoundEvent? bestOrnament;
    double? bestOrnamentDelta;

    // Com a janela adaptativa, o primeiro que serve (os pendentes estão em
    // ordem de `onMs`): o mais antigo.
    bool better(double delta, double? current) =>
        current == null || (!adaptiveWindow && delta.abs() < current.abs());

    for (final e in _pending) {
      if (e.pitch != pitch) continue;
      final delta = musicalMs - e.onMs;
      final inner = _inner[e];
      if (inner != null) {
        // A nota de dentro de um grupo: a janela é a do grupo todo, e vale a
        // mais antiga ainda pendente dessa altura.
        if (musicalMs < inner.startMs || musicalMs > inner.endMs) continue;
        if (best == null) {
          best = e;
          bestDelta = delta;
        }
        continue;
      }
      if (!_inWindow(e, delta)) continue;
      if (e.ornament) {
        if (better(delta, bestOrnamentDelta)) {
          bestOrnament = e;
          bestOrnamentDelta = delta;
        }
      } else if (better(delta, bestDelta)) {
        best = e;
        bestDelta = delta;
      }
    }
    return (best: best, bestDelta: bestDelta, ornament: bestOrnament);
  }

  /// [hit] foi a nota de dentro do grupo [group] que a tecla casou: as de dentro
  /// que vinham antes dela e ainda estão pendentes ficam para trás (`missed`).
  void _skipBefore(SoundEvent hit, _Fioritura group) {
    final at = group.order.indexOf(hit);
    for (var i = 0; i < at; i++) {
      final skipped = group.order[i];
      if (!_pending.remove(skipped)) continue;
      _verdicts.add(
        NoteVerdict(
          eventId: skipped.id,
          pitch: skipped.pitch,
          kind: PracticeVerdictKind.missed,
          deltaMs: 0,
        ),
      );
    }
  }

  /// Uma nota de altura [pitch] soa em [ms] (ver [forgiveSounding]).
  bool _sounding(int pitch, double ms) {
    final spans = _ornamentSpans ??= _buildOrnamentSpans();
    for (final e in _all) {
      if (e.onMs - _okMs > ms) break;
      if (e.pitch != pitch) continue;
      var offMs = e.offMs;
      final span = spans[e.id];
      if (span != null && span.offMs > offMs) offMs = span.offMs;
      if (ms <= offMs) return true;
    }
    return false;
  }

  Map<String, ({double onMs, double offMs})> _buildOrnamentSpans() {
    final ids = {
      for (final e in _all)
        if (e.ornament) e.id,
    };
    final spans = <String, ({double onMs, double offMs})>{};
    for (final e in _all) {
      if (!ids.contains(e.id)) continue;
      final span = spans[e.id];
      spans[e.id] = span == null
          ? (onMs: e.onMs, offMs: e.offMs)
          : (
              onMs: e.onMs < span.onMs ? e.onMs : span.onMs,
              offMs: e.offMs > span.offMs ? e.offMs : span.offMs,
            );
    }
    return spans;
  }

  /// Avança o relógio musical: eventos cuja janela (`onMs + janelaMax`) já
  /// passou sem casar viram `missed` — exceto ornamentos, que somem em
  /// silêncio (não cobrados na 1.0). Os ataques de cifra cuja janela fechou
  /// viram `correct`/`early`/`late` ou `missed` (ver [_decideChord]).
  void tick(double musicalNowMs) {
    _expire(musicalNowMs);
    _expireChords(musicalNowMs);
  }

  /// Há nota do aluno, ou ataque de cifra, ainda sem veredito cujo ataque cai em
  /// `[startMs, endMs)` (ornamentos não contam: somem em silêncio). É o que a
  /// volta na hora consulta para saber se um compasso já está decidido.
  bool hasPendingIn(double startMs, double endMs) =>
      _pending.any((e) => !e.ornament && e.onMs >= startMs && e.onMs < endMs) ||
      _chords.any((a) => a.onMs >= startMs && a.onMs < endMs);

  /// O [tick], só para [pitch] quando dado.
  void _expire(double musicalNowMs, {int? pitch}) {
    _pending.removeWhere((e) {
      if (pitch != null && e.pitch != pitch) return false;
      if (musicalNowMs <= _windowEnd(e)) return false;
      if (!e.ornament) {
        _verdicts.add(
          NoteVerdict(
            eventId: e.id,
            pitch: e.pitch,
            kind: PracticeVerdictKind.missed,
            deltaMs: 0,
          ),
        );
      }
      return true;
    });
  }

  /// T04 (loop A-B): reinicia a partir de `musicalMs`, descartando o que já
  /// tinha sido casado ou perdido antes dele.
  ///
  /// [untilMs] (exclusivo) limita o fim do trecho — o loop A-B só cobra o que
  /// cai em `[musicalMs, untilMs)`.
  void resetTo(double musicalMs, {double? untilMs}) {
    _beyond = untilMs == null
        ? const []
        : _all.where((e) => e.onMs >= untilMs).toList();
    _pending = _all
        .where(
          (e) =>
              e.onMs >= musicalMs - kRangeBoundaryToleranceMs &&
              (untilMs == null || e.onMs < untilMs),
        )
        .toList();
    // As notas do app fora dessa janela (antes do começo, com a tolerância, ou a
    // partir do fim) absorvem um toque cada. A da folga da barra cai antes do fim
    // do compasso que repete, mas é do que vem depois.
    final windowStart = musicalMs - kRangeBoundaryToleranceMs;
    _absorbers = [
      for (final e in _appNotes)
        if (e.onMs < windowStart || (untilMs != null && e.onMs >= untilMs)) e,
    ];
    // Os acordes do trecho voltam abertos, sem as teclas da tentativa anterior.
    _beyondChords = untilMs == null
        ? const []
        : _chordsAll.where((a) => a.onMs >= untilMs).toList();
    _chords = [
      for (final a in _chordsAll)
        if (a.onMs >= musicalMs - kRangeBoundaryToleranceMs &&
            (untilMs == null || a.onMs < untilMs))
          a.fresh(),
    ];
  }

  void dispose() => unawaited(_verdicts.close());
}

/// Um grupo irregular longo da [RealtimeSession]: as notas de dentro, na
/// ordem, e a janela do grupo todo.
class _Fioritura {
  _Fioritura({required this.startMs, required this.endMs});

  final double startMs;
  final double endMs;
  final List<SoundEvent> order = [];
}

/// A janela que sobra do vizinho: [share] do intervalo até ele, se for menor que
/// [limit]; sem vizinho, [limit].
double _capGap(double? gap, double share, double limit) =>
    gap == null || gap * share >= limit ? limit : gap * share;

/// Um ataque de cifra na [RealtimeSession] (AC05b): a exigência, a janela dela
/// (antes do ataque, [early]; depois, [late]; a de certo, [ok]) e as teclas que
/// o aluno apertou nela, com o instante do primeiro toque de cada uma.
class _ChordAttack {
  _ChordAttack(
    this.demand, {
    required this.early,
    required this.late,
    required this.ok,
  });

  final ChordDemand demand;
  final double early;
  final double late;
  final double ok;

  /// As teclas que a exigência aceita, apertadas dentro da janela (tecla → ms).
  final Map<int, double> pressed = {};

  double get onMs => demand.onMs;

  /// O fim da janela: o ataque decide-se aqui.
  double get endMs => onMs + late;

  /// O mesmo ataque, sem teclas (a sessão refaz os abertos a cada [resetTo]).
  _ChordAttack fresh() =>
      _ChordAttack(demand, early: early, late: late, ok: ok);
}
