// PerformanceTrack (N03): camada de consulta sobre `VsbMidi` — janela de
// tempo, pauta, acordes. Não funde ligadura nem expande ornamento: G02 já
// entrega isso pronto em `VsbMidi.notes`/`.pedal` (ver
// docs/plano/N03-performance-track.md).

import 'package:flutter/foundation.dart';
import 'package:score_bridge/score_bridge.dart';

/// Os limites de compasso do timemap saem arredondados para ms inteiros
/// (9231) enquanto a nota na barra tem a fração (9230,77): sem folga, a
/// primeira nota do compasso seguinte cairia no trecho anterior e a última
/// do trecho, no seguinte. Um intervalo `[start, end)` vale, para as notas,
/// como `[start - tol, end - tol)`.
const double kRangeBoundaryToleranceMs = 1;

/// Uma tecla apertada, pronta para tocar: `onMs`/`offMs` já são o relógio
/// final (ligadura fundida, ornamento expandido, em ms musicais).
@immutable
class SoundEvent {
  final String id;
  final int pitch;
  final double onMs;
  final double offMs;
  final int staff;
  final int channel;
  final int program;
  final int velocity;
  final bool ornament;

  /// O grupo irregular de que a nota faz parte (T11, a *fioritura*), ou
  /// `null`. As notas de um mesmo grupo têm o mesmo número; a sessão em tempo
  /// real cobra as de dentro na ordem, sem a janela de cada uma (ver
  /// [PerformanceTrack.withOrnaments], `groups`).
  final int? groupId;

  /// Ids das notas de continuação da ligadura (`MidiNote.tied`): não soam
  /// de novo, mas acendem junto com esta — é uma tecla só.
  final List<String> tied;

  /// A nota que o app toca seja qual for a mão do aluno (o compasso de ouça
  /// do eco, issue 22). Sai sempre como ornamento: soa e não se cobra.
  final bool byApp;

  const SoundEvent({
    required this.id,
    required this.pitch,
    required this.onMs,
    required this.offMs,
    required this.staff,
    required this.channel,
    required this.program,
    required this.velocity,
    required this.ornament,
    this.tied = const [],
    this.groupId,
    this.byApp = false,
  });
}

@immutable
class PedalEvent {
  final String id;
  final double timeMs;
  final PedalDir dir;
  final int staff;
  final int channel;

  const PedalEvent({
    required this.id,
    required this.timeMs,
    required this.dir,
    required this.staff,
    required this.channel,
  });
}

/// Uma nota de um ornamento escrito por extenso (T10): a altura e o trecho
/// da nota principal em que ela soa, em frações da duração dela (0 é o
/// começo, 1 o fim). O exportador MIDI do Verovio só expande o trêmolo; o
/// trilo, o mordente e o grupeto saem como a nota escrita, e quem sabe o que
/// eles tocam (o host) passa a expansão a [PerformanceTrack.withOrnaments].
@immutable
class OrnamentNote {
  const OrnamentNote(this.pitch, this.start, this.end);

  final int pitch;
  final double start;
  final double end;
}

/// Notas da mesma pauta com `onMs` a até [PerformanceTrack.chordToleranceMs]
/// uma da outra (arpejos escritos não entram aqui — já vêm como onsets
/// escalonados do Verovio).
@immutable
class Chord {
  final double onMs;
  final int staff;
  final List<SoundEvent> notes;

  const Chord({required this.onMs, required this.staff, required this.notes});
}

/// O que [PerformanceTrack.withOrnaments] acrescenta à trilha. Sem nada, a
/// trilha volta como está.
class OrnamentPlan {
  const OrnamentPlan({
    this.expand = const {},
    this.free = const {},
    this.tremoloHeads = false,
    this.groups = const {},
    this.app = const {},
  });

  /// Notas que cada evento (pelo id) vira, em ornamento.
  final Map<String, List<OrnamentNote>> expand;

  /// Eventos (pelo id) que saem também como ornamento.
  final Set<String> free;

  /// A primeira nota de cada altura do trêmolo sai como cabeça.
  final bool tremoloHeads;

  /// Grupos irregulares: o id do evento e o grupo dele.
  final Map<String, int> groups;

  /// Eventos (pelo id) que a própria pessoa toca (o app os marca).
  final Set<String> app;

  bool get isEmpty =>
      expand.isEmpty &&
      free.isEmpty &&
      !tremoloHeads &&
      groups.isEmpty &&
      app.isEmpty;
}

/// Os campos que uma cópia de evento troca (ver `PerformanceTrack._copy`); o
/// que não vem fica como está.
class _Change {
  const _Change({
    this.pitch,
    this.onMs,
    this.offMs,
    this.ornament,
    this.tied,
    this.groupId,
    this.byApp,
  });

  final int? pitch;
  final double? onMs;
  final double? offMs;
  final bool? ornament;
  final List<String>? tied;
  final int? groupId;
  final bool? byApp;
}

/// Estrutura Dart pura, construída uma vez por `.vsb`, que responde a tudo
/// que som, MIDI e treino precisam perguntar sobre "o que soa quando".
class PerformanceTrack {
  /// Tolerância usada por [chords] para agrupar notas da mesma pauta.
  static const double chordToleranceMs = 30;

  /// Ordenado por [SoundEvent.onMs], depois [SoundEvent.pitch].
  final List<SoundEvent> events;

  /// Ordenado por [PedalEvent.timeMs].
  final List<PedalEvent> pedal;

  final double durationMs;
  final Set<int> staves;

  PerformanceTrack._({
    required this.events,
    required this.pedal,
    required this.durationMs,
    required this.staves,
  });

  /// Adapta `doc.midi` (`VsbMidi`, do bridge) para eventos de consulta.
  /// `document.midi == null` (peça sem `midi.json`) vira uma track vazia,
  /// não um erro.
  factory PerformanceTrack.fromDocument(VsbDocument doc) {
    final midi = doc.midi;
    if (midi == null) {
      return PerformanceTrack._(
        events: const [],
        pedal: const [],
        durationMs: 0,
        staves: const {},
      );
    }

    final events = _notesOf(midi);
    final pedal = _pedalsOf(midi);

    var durationMs = 0.0;
    for (final e in events) {
      if (e.offMs > durationMs) durationMs = e.offMs;
    }
    for (final p in pedal) {
      if (p.timeMs > durationMs) durationMs = p.timeMs;
    }

    return PerformanceTrack._(
      events: events,
      pedal: pedal,
      durationMs: durationMs,
      staves: events.map((e) => e.staff).toSet(),
    );
  }

  /// Track a partir de eventos já prontos (testes com partitura sintética).
  @visibleForTesting
  factory PerformanceTrack.fromEvents(List<SoundEvent> events) {
    final sorted = List<SoundEvent>.of(events)
      ..sort((a, b) {
        final byOnMs = a.onMs.compareTo(b.onMs);
        return byOnMs != 0 ? byOnMs : a.pitch.compareTo(b.pitch);
      });
    return PerformanceTrack._(
      events: sorted,
      pedal: const [],
      durationMs: sorted.fold(0.0, (m, e) => e.offMs > m ? e.offMs : m),
      staves: sorted.map((e) => e.staff).toSet(),
    );
  }

  /// A mesma track sem as notas de [ids]: não soam e não se cobram (o treino que
  /// pede só a parte do aluno, sem acompanhamento).
  PerformanceTrack without(Set<String> ids) {
    if (ids.isEmpty) return this;
    return PerformanceTrack._(
      events: [
        for (final e in events)
          if (!ids.contains(e.id)) e,
      ],
      pedal: pedal,
      durationMs: durationMs,
      staves: staves,
    );
  }

  /// O que não se cobra, marcado como ornamento (T10), e o ornamento escrito
  /// que soa por extenso:
  ///
  /// - [expand]: id da nota → as notas do ornamento ([OrnamentNote]). O
  ///   evento vira as notas, todas com o id dele; a primeira com a altura
  ///   escrita é a principal e é cobrada (fica com a ligadura), as outras são
  ///   ornamento. Sem nenhuma na altura escrita, a primeira é a cobrada.
  /// - [free]: ids que não se cobram (a apojatura breve): viram ornamento.
  /// - [tremoloHeads]: no ornamento que o Verovio expandiu (o trêmolo, várias
  ///   entradas do mesmo id com `ornament`), a primeira nota de cada altura é
  ///   cobrada; as outras continuam ornamento.
  /// - [groups]: id da nota → o grupo irregular dela (T11, a *fioritura* de 9
  ///   notas ou mais): o evento ganha [SoundEvent.groupId].
  /// - [app]: ids que o app toca e não se cobram (issue 22): viram ornamento com
  ///   [SoundEvent.byApp]. Vencem os outros ramos: a principal de um
  ///   ornamento por extenso também sai assim, e a cabeça do trêmolo não
  ///   volta a ser cobrada.
  ///
  /// Sem nada disso, devolve a própria track.
  PerformanceTrack withOrnaments({OrnamentPlan plan = const OrnamentPlan()}) {
    if (plan.isEmpty) return this;
    final expand = plan.expand;
    final free = plan.free;
    final tremoloHeads = plan.tremoloHeads;
    final groups = plan.groups;
    final app = plan.app;
    final heads = <String, Set<int>>{};
    final out = <SoundEvent>[];
    // Todo evento que sai daqui passa por aqui: o id em [app] vence o ramo
    // que o montou (ornamento, cabeça do trêmolo ou a cópia de `free`).
    void emit(SoundEvent x) {
      out.add(
        app.contains(x.id)
            ? _copy(x, const _Change(ornament: true, byApp: true))
            : x,
      );
    }

    for (final e in events) {
      final notes = expand[e.id];
      if (notes != null && notes.isNotEmpty && !e.ornament) {
        _expandNotes(e, notes, emit);
      } else if (free.contains(e.id)) {
        emit(_copy(e, const _Change(ornament: true)));
      } else if (tremoloHeads &&
          e.ornament &&
          (heads[e.id] ??= {}).add(e.pitch)) {
        emit(_copy(e, const _Change(ornament: false)));
      } else {
        emit(e);
      }
    }
    _assignGroups(out, groups);
    _sortByOnset(out);
    return PerformanceTrack._(
      events: out,
      pedal: pedal,
      durationMs: durationMs,
      staves: staves,
    );
  }

  /// As notas que [e] vira (um ornamento escrito por extenso): a principal, a
  /// de altura igual à de [e] (ou a primeira), leva a ligadura; as outras, são
  /// ornamento. Cada uma cai no trecho dela da duração de [e].
  static void _expandNotes(
    SoundEvent e,
    List<OrnamentNote> notes,
    void Function(SoundEvent) emit,
  ) {
    final length = e.offMs - e.onMs;
    var principal = notes.indexWhere((n) => n.pitch == e.pitch);
    if (principal < 0) principal = 0;
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      emit(
        _copy(
          e,
          _Change(
            pitch: n.pitch,
            onMs: e.onMs + n.start * length,
            offMs: e.onMs + n.end * length,
            ornament: i != principal,
            tied: i == principal ? e.tied : const [],
          ),
        ),
      );
    }
  }

  /// Põe o grupo de cada evento cujo id está em [groups] (grupos irregulares).
  static void _assignGroups(List<SoundEvent> out, Map<String, int> groups) {
    if (groups.isEmpty) return;
    for (var i = 0; i < out.length; i++) {
      final group = groups[out[i].id];
      if (group != null) out[i] = _copy(out[i], _Change(groupId: group));
    }
  }

  /// Ordena por ataque e, empatando, por altura.
  static void _sortByOnset(List<SoundEvent> out) => out.sort((a, b) {
    final byOnMs = a.onMs.compareTo(b.onMs);
    return byOnMs != 0 ? byOnMs : a.pitch.compareTo(b.pitch);
  });

  /// As notas do `midi.json`, na ordem de ataque (e de altura, empatando).
  static List<SoundEvent> _notesOf(VsbMidi midi) =>
      midi.notes
          .map(
            (note) => SoundEvent(
              id: note.id,
              pitch: note.pitch,
              onMs: note.onMs,
              offMs: note.offMs,
              staff: note.staff,
              channel: note.channel,
              program: note.program,
              velocity: note.velocity,
              ornament: note.ornament,
              tied: note.tied,
            ),
          )
          .toList()
        ..sort((a, b) {
          final byOnMs = a.onMs.compareTo(b.onMs);
          return byOnMs != 0 ? byOnMs : a.pitch.compareTo(b.pitch);
        });

  /// Os pedais do `midi.json`, na ordem do tempo.
  static List<PedalEvent> _pedalsOf(VsbMidi midi) =>
      midi.pedal
          .map(
            (p) => PedalEvent(
              id: p.id,
              timeMs: p.timeMs,
              dir: p.dir,
              staff: p.staff,
              channel: p.channel,
            ),
          )
          .toList()
        ..sort((a, b) => a.timeMs.compareTo(b.timeMs));

  /// Uma cópia de [e] com os campos de [change] trocados (o que não vem fica).
  static SoundEvent _copy(SoundEvent e, [_Change change = const _Change()]) =>
      SoundEvent(
        id: e.id,
        pitch: change.pitch ?? e.pitch,
        onMs: change.onMs ?? e.onMs,
        offMs: change.offMs ?? e.offMs,
        staff: e.staff,
        channel: e.channel,
        program: e.program,
        velocity: e.velocity,
        ornament: change.ornament ?? e.ornament,
        tied: change.tied ?? e.tied,
        groupId: change.groupId ?? e.groupId,
        byApp: change.byApp ?? e.byApp,
      );

  /// Recorte para as sessões de um intervalo com saltos (J08): só eventos
  /// com `onMs` em `[startMs, endMs)` fora dos vãos. Sem pedal (as sessões
  /// não usam). O agendador continua na peça cheia, com teto e saltos.
  PerformanceTrack rangeView({
    required double startMs,
    required double endMs,
    List<({double startMs, double endMs})> gaps = const [],
  }) {
    bool inGap(double ms) {
      for (final gap in gaps) {
        if (ms >= gap.startMs && ms < gap.endMs) return true;
      }
      return false;
    }

    final filtered = [
      for (final e in events)
        if (e.onMs >= startMs - kRangeBoundaryToleranceMs &&
            e.onMs < endMs - kRangeBoundaryToleranceMs &&
            !inGap(e.onMs))
          e,
    ];
    return PerformanceTrack._(
      events: filtered,
      pedal: const [],
      durationMs: durationMs,
      staves: filtered.map((e) => e.staff).toSet(),
    );
  }

  /// Eventos com `onMs` em `[fromMs, toMs)`. Busca binária em [events]
  /// (ordenado por `onMs`) — o agendador (K04) chama isto a cada ~25 ms.
  ///
  /// O evento [SoundEvent.byApp] sai mesmo fora de [staves]: o agendador toca
  /// a nota do app com o filtro da mão (com as duas mãos o filtro é vazio e
  /// nada mais toca).
  Iterable<SoundEvent> startingIn(
    double fromMs,
    double toMs, {
    Set<int>? staves,
  }) sync* {
    for (var i = _lowerBound(fromMs); i < events.length; i++) {
      final e = events[i];
      if (e.onMs >= toMs) break;
      if (staves == null || staves.contains(e.staff) || e.byApp) yield e;
    }
  }

  /// Eventos soando em [ms] (`onMs <= ms < offMs`).
  Iterable<SoundEvent> soundingAt(double ms, {Set<int>? staves}) sync* {
    for (final e in events) {
      if (e.onMs > ms) break;
      if (ms < e.offMs && (staves == null || staves.contains(e.staff))) {
        yield e;
      }
    }
  }

  /// Agrupa [events] das pautas em [staves] em acordes (mesma pauta,
  /// `onMs` a até [chordToleranceMs] um do outro), ordenados por `onMs`.
  List<Chord> chords({required Set<int> staves}) {
    final result = <Chord>[];
    for (final staff in staves) {
      final staffEvents = events.where((e) => e.staff == staff).toList();
      List<SoundEvent>? current;
      var anchorMs = 0.0;
      for (final e in staffEvents) {
        if (current != null && e.onMs - anchorMs <= chordToleranceMs) {
          current.add(e);
        } else {
          if (current != null) {
            result.add(Chord(onMs: anchorMs, staff: staff, notes: current));
          }
          current = [e];
          anchorMs = e.onMs;
        }
      }
      if (current != null) {
        result.add(Chord(onMs: anchorMs, staff: staff, notes: current));
      }
    }
    result.sort((a, b) => a.onMs.compareTo(b.onMs));
    return result;
  }

  /// Primeiro índice em [events] com `onMs >= fromMs`.
  int _lowerBound(double fromMs) {
    var lo = 0;
    var hi = events.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (events[mid].onMs < fromMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
