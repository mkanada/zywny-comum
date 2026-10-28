// T01: núcleo do treino, Dart puro — sem UI, sem hardware (M02/M03) e sem
// relógio de parede embutido. Quem chama decide o tempo (`atMs`/`musicalMs`)
// e faz a conversão de segundos de dispositivo para ms musicais (isso é do
// agendador, K04, e do relógio de treino, T02/T03); ver
// docs/plano/T01-casador-de-notas.md.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zywny_audio/performance_track.dart';

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
  });

  /// Id do [SoundEvent] casado; `null` em [PracticeVerdictKind.wrong] (não
  /// há candidato).
  final String? eventId;
  final int pitch;
  final PracticeVerdictKind kind;

  /// tocada − esperada, em ms: musicais no modo tempo real, de parede desde
  /// a primeira nota do acorde no modo espera. `0` em `wrong`/`missed`.
  final double deltaMs;

  /// Guardada para uso futuro — não avaliada na 1.0 (D-TREINO).
  final int velocity;

  @override
  String toString() =>
      'NoteVerdict($kind pitch=$pitch Δ=${deltaMs.toStringAsFixed(1)}ms'
      '${eventId != null ? " id=$eventId" : ""})';
}

/// Um passo do modo espera: acordes de todas as pautas do aluno com o mesmo
/// `onMs`, fundidos num só. `remaining` é republicado a cada nota certa
/// tocada (mesmo `index`/`onMs`/`notes`), para a UI destacar só o que falta.
@immutable
class PracticeStep {
  const PracticeStep({
    required this.index,
    required this.onMs,
    required this.notes,
    required this.remaining,
  });

  final int index;
  final double onMs;
  final List<SoundEvent> notes;
  final Set<int> remaining;
}

/// Janela de parede, em ms, para as notas de um mesmo acorde no modo
/// espera valerem como "juntas": da primeira à última nota certa do acorde
/// não pode passar disto. Não é `missed` (o modo espera nunca marca falta):
/// se estourar, a tentativa recomeça — as notas ainda seguradas continuam
/// valendo (estão soando junto com o ataque atual), o resto volta a faltar.
const double kWaitChordWindowMs = 300;

/// Modo espera (T01): o tempo não anda até o acorde certo ser tocado.
/// Dirigido só por [noteOn]/[noteOff] — sem relógio interno.
///
/// O acorde fecha quando todas as notas dele estão apertadas juntas e
/// nenhuma tecla errada está apertada: é o estado das teclas que decide, não
/// a ordem. Uma errada no meio não zera a tentativa — soltá-la com o acorde
/// todo seguro fecha o passo. Teclas que já estavam apertadas quando o passo
/// começou (a mão ainda no acorde anterior, no legato) não contam como
/// erradas: só as apertadas durante o passo.
class WaitModeSession {
  WaitModeSession(
    List<PracticeStep> steps, {
    this._chordWindowMs = kWaitChordWindowMs,
  }) : _steps = steps {
    _startStep(0);
  }

  /// Funde os acordes das pautas do aluno pelo mesmo `onMs` (N03 já agrupa
  /// por pauta, com tolerância de [PerformanceTrack.chordToleranceMs]; aqui
  /// só junta pautas diferentes que caem no mesmo instante). Notas de
  /// ornamento (`SoundEvent.ornament`) não entram nos passos — D-TREINO não
  /// cobra ornamento na 1.0, o aluno não precisa tocá-las.
  factory WaitModeSession.forStaves(
    PerformanceTrack track, {
    required Set<int> staves,
    double chordWindowMs = kWaitChordWindowMs,
  }) {
    final byOnMs = <double, List<SoundEvent>>{};
    for (final chord in track.chords(staves: staves)) {
      final notes = chord.notes.where((e) => !e.ornament).toList();
      if (notes.isEmpty) continue;
      byOnMs.putIfAbsent(chord.onMs, () => []).addAll(notes);
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
        ),
    ];
    return WaitModeSession(steps, chordWindowMs: chordWindowMs);
  }

  final List<PracticeStep> _steps;

  /// Ver [kWaitChordWindowMs].
  final double _chordWindowMs;
  int _index = 0;
  final Set<int> _held = {};
  Set<int> _remaining = {};
  Set<int> _blocked = {};
  double? _firstHitAtMs;

  /// Notas certas do acorde pendente, ainda sem veredito: o `correct` só
  /// sai quando o acorde fecha, todas juntas — antes disso a UI continua
  /// mostrando o acorde inteiro como esperado.
  final Map<int, ({double atMs, int velocity})> _hits = {};

  /// Teclas erradas apertadas durante o passo e ainda seguradas: enquanto
  /// houver alguma, o acorde não fecha.
  final Set<int> _wrongHeld = {};

  final ValueNotifier<PracticeStep?> _current = ValueNotifier(null);

  /// Passo atual, com `remaining` sempre atualizado; `null` quando a peça
  /// acabou.
  ValueListenable<PracticeStep?> get current => _current;

  final StreamController<NoteVerdict> _verdicts =
      StreamController<NoteVerdict>.broadcast(sync: true);

  /// `sync: true`: emissão é uma decisão pura e imediata de [noteOn]/
  /// [noteOff], sem I/O — o padrão assíncrono só obrigaria os testes a
  /// aguardar uma volta de event loop por chamada sem trazer benefício.
  Stream<NoteVerdict> get verdicts => _verdicts.stream;

  bool get done => _index >= _steps.length;

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

    if (!_remaining.contains(pitch)) {
      // Nota que já vale no acorde (repetida sem soltar) não é erro.
      if (_steps[_index].notes.any((e) => e.pitch == pitch)) return;
      // Errada: o acorde não fecha enquanto ela estiver apertada. As certas
      // já seguradas continuam valendo.
      _wrongHeld.add(pitch);
      _verdicts.add(
        NoteVerdict(
          pitch: pitch,
          kind: PracticeVerdictKind.wrong,
          deltaMs: 0,
          velocity: velocity,
        ),
      );
      return;
    }

    _firstHitAtMs ??= atMs;
    _remaining.remove(pitch);
    _hits[pitch] = (atMs: atMs, velocity: velocity);
    _completeOrPublish();
  }

  /// Fecha o passo se o acorde está todo apertado e nenhuma errada está;
  /// senão republica o que falta.
  void _completeOrPublish() {
    if (_remaining.isEmpty && _wrongHeld.isEmpty) {
      _completeStep();
    } else {
      _publish(_steps[_index]);
    }
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
    _startStep(_index + 1);
  }

  /// Tecla solta: limpa o bloqueio de "precisa soltar e apertar de novo"
  /// para essa tecla. Soltar uma nota certa antes de o acorde fechar a faz
  /// faltar de novo: o acorde só vale com todas as notas juntas. Soltar a
  /// última errada com o acorde todo apertado fecha o passo.
  void noteOff(int pitch) {
    _held.remove(pitch);
    _blocked.remove(pitch);
    final wasWrong = _wrongHeld.remove(pitch);
    if (done) return;
    if (wasWrong) {
      if (_remaining.isEmpty && _wrongHeld.isEmpty) _completeStep();
      return;
    }
    final step = _steps[_index];
    if (!_remaining.contains(pitch) &&
        step.notes.any((e) => e.pitch == pitch)) {
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
    final index = _steps.indexWhere((s) => s.onMs >= onMs);
    _startStep(index == -1 ? _steps.length : index);
  }

  void _startStep(int index) {
    _index = index;
    if (done) {
      _remaining = {};
      _blocked = {};
      _current.value = null;
      return;
    }
    final step = _steps[index];
    _remaining = step.notes.map((e) => e.pitch).toSet();
    _blocked = _held.intersection(_remaining);
    _hits.clear();
    // O que ainda está apertado de antes não é erro deste passo.
    _wrongHeld.clear();
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
    _completeOrPublish();
  }

  void _publish(PracticeStep step) {
    _current.value = PracticeStep(
      index: step.index,
      onMs: step.onMs,
      notes: step.notes,
      remaining: Set.of(_remaining),
    );
  }

  void dispose() {
    _current.dispose();
    unawaited(_verdicts.close());
  }
}

/// Modo tempo real (T01): casa notas tocadas — já convertidas para ms
/// musicais pela camada de cima (K04) — contra a janela de cada evento
/// esperado. Dirigido por [noteOn] e por [tick] (que marca `missed`).
class RealtimeSession {
  RealtimeSession(
    List<SoundEvent> events, {
    required this.speed,
    this.windowOkMs = 75,
    this.windowMaxMs = 150,
    this.adaptiveWindow = false,
    this.forgiveSounding = false,
  }) : _all = List<SoundEvent>.of(events)
         ..sort((a, b) => a.onMs.compareTo(b.onMs)) {
    _pending = List<SoundEvent>.of(_all);
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
  }) {
    final events = track.events.where((e) => staves.contains(e.staff));
    return RealtimeSession(
      events.toList(),
      speed: speed,
      windowOkMs: windowOkMs,
      windowMaxMs: windowMaxMs,
      adaptiveWindow: adaptiveWindow,
      forgiveSounding: forgiveSounding,
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
        double cap(double? gap, double share, double limit) =>
            gap == null || gap * share >= limit ? limit : gap * share;
        final ok = cap(before, 0.5, cap(after, 0.5, windowOkMs));
        _windowOf[e] = (
          early: cap(before, 0.5, windowMaxMs),
          late: cap(after, 0.75, windowMaxMs),
          ok: ok,
        );
      }
    }
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
    if (adaptiveWindow) _expire(musicalMs, pitch: pitch);
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

    if (best != null) {
      final inner = _inner[best];
      if (inner != null) _skipBefore(best, inner);
      _pending.remove(best);
      final delta = bestDelta!;
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

    if (bestOrnament != null) {
      _pending.remove(bestOrnament);
      return;
    }

    if (forgiveSounding && _sounding(pitch, musicalMs)) return;

    _verdicts.add(
      NoteVerdict(
        pitch: pitch,
        kind: PracticeVerdictKind.wrong,
        deltaMs: 0,
        velocity: velocity,
      ),
    );
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
  /// silêncio (não cobrados na 1.0).
  void tick(double musicalNowMs) => _expire(musicalNowMs);

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
    _pending = _all
        .where(
          (e) => e.onMs >= musicalMs && (untilMs == null || e.onMs < untilMs),
        )
        .toList();
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
