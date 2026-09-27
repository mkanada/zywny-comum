// `ScorePlayer` (A05a/A05b): o host simulado. Um relógio próprio lê o timemap
// embutido no `.vsb` e acende/apaga as notas no `ScoreController`; a haste de
// virada e a página corrente saem da posição, por função pura
// (`ScoreTimeline.curtainAt`).
//
// RELÓGIO: um `Ticker` em milissegundos musicais (`posição += delta * speed`),
// nunca `DateTime.now()` — o teste usa tempo simulado (`tester.pump`) ou chama
// [advance] direto. `pause`/`play` não movem a posição e não tocam nas
// animações em curso do controller (que têm o relógio delas).
//
// RELÓGIO PLUGÁVEL (C01): com [ScorePlayer.clock] definido, quem manda é
// `clock.positionMs` a cada tick — `speed` deixa de valer (a fonte já dá
// posição musical). Posição adiantou: aplica como [advance] até lá. Recuou
// mais que 20 ms (o host fez seek no áudio): refaz como [seek]. Recuou menos
// que isso (jitter do relógio de áudio interpolado): ignora — parada
// (posição não anda) também não faz nada, é o modo espera (T02). `play`/
// `pause` continuam só ligando/desligando o `Ticker`; o host coordena os
// dois relógios.
//
// A CADA AVANÇO aplicam-se **todas** as entradas com `tstamp` ultrapassado
// desde o último tick, não só a próxima: com `speed` alto ou um frame perdido,
// pular entradas deixaria notas acesas para sempre. `seek` recalcula do zero:
// apaga os destaques (as cores fixas do host ficam) e acende exatamente as
// notas que o timemap diz estarem ativas no instante.
//
// LIGAÇÃO COM A VISTA: `curtain` é o `ValueListenable` para `ScoreView.curtain`.
// Sem haste, o player leva a vista à página de repouso (`showPage`) só quando
// ela difere; em `continuousScroll` não há haste, e a rolagem acompanha o
// compasso corrente (`scrollToId`).
//
// PÁGINAS ALTERNATIVAS (P04b): a página de repouso e a de trás da haste vêm
// de `ScoreTimeline.restViewAt`/`curtainAt` (a rota de P00/P04a) — em
// execução, a vista pode mostrar uma alternativa num salto de repetição.
// `currentPage`/`goToPage` (do host, parado) continuam só na numeração
// normal (D-ALT-INDICE); é `displayedPage` que muda. `continuousScroll` não
// participa da rota: sempre a faixa de páginas normais, por `scrollToId`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/painting.dart' show Color;

import 'model.dart';
import 'score_controller.dart';
import 'score_timeline.dart';
import 'score_view.dart';

export 'score_timeline.dart' show MeasureInfo, ScoreTimeline;

/// Quanto tempo um destaque "sem fim conhecido" espera pelo `off`: acima de
/// qualquer peça.
const _kForever = Duration(days: 365);

/// Abaixo disso, uma posição de [PlaybackClock] que recuou é jitter do
/// relógio de áudio interpolado, não um seek do host — ignore.
const _kClockSeekToleranceMs = 20.0;

/// Fonte de posição musical, em ms, que o [ScorePlayer] pode ler no lugar de
/// avançar sozinho por `delta * speed` (C01) — ver RELÓGIO PLUGÁVEL no
/// cabeçalho do arquivo.
abstract class PlaybackClock {
  /// Posição musical atual, em ms.
  double get positionMs;

  /// Se a fonte está tocando (reservado para o host coordenar `play`/
  /// `pause`; o `ScorePlayer` não lê isto — K04).
  bool get isRunning;
}

class ScorePlayer {
  ScorePlayer({
    required this.document,
    required this.controller,
    this.view,
    this.release = const Duration(milliseconds: 500),
    this.highlightColor = kDefaultHighlightColor,
    this.maxSweepDuration,
    this.barWidth,
    this.scrollAlignment = 0.3,
    this.scrollDuration = const Duration(milliseconds: 300),
    this.singleNoteDelay = const Duration(milliseconds: 500),
    this.onEntry,
    // Repassado a `ScoreTimeline` (P04a): `false` desliga a rota de páginas
    // alternativas — a vista, em execução, só mostra páginas normais, como
    // antes de P04a/P04b.
    bool useAlternates = true,
  }) : timeline = ScoreTimeline(document, useAlternates: useAlternates) {
    _measureIndex = ValueNotifier<int>(0);
    _tempo = ValueNotifier<double?>(null);
    _publish(force: true);
  }

  final VsbDocument document;
  final ScoreController controller;

  /// A vista a acompanhar (página de repouso e rolagem). Opcional: sem ela o
  /// player só destaca notas e publica a haste.
  final ScoreViewController? view;

  /// Duração do `release` de cada nota ao chegar o `off`.
  final Duration release;

  /// Cor do destaque; mutável para o host trocar sem recriar o player (o
  /// painel de opções do zywny, por exemplo). Só vale para a **próxima** nota
  /// que acender — não recolore as que já estão em `attack`/`hold`.
  Color highlightColor;

  /// Onde, na viewport, o compasso corrente fica no modo contínuo.
  final double scrollAlignment;
  final Duration scrollDuration;

  /// Atraso da conclusão da virada na página de uma nota só (0,5 s).
  final Duration singleNoteDelay;

  /// Chamado para cada entrada do timemap aplicada, na ordem (uma por
  /// instante do timemap; não é chamado no `seek`).
  final void Function(TimemapEntry entry)? onEntry;

  final ScoreTimeline timeline;

  /// Teto de cada movimento da haste e largura dela; `null` lê da vista (ou
  /// usa os padrões). Se personalizar, passe os **mesmos** valores ao
  /// `ScoreView`.
  final Duration? maxSweepDuration;
  final double? barWidth;

  late final ValueNotifier<int> _measureIndex;
  late final ValueNotifier<double?> _tempo;
  final ValueNotifier<SweepCurtain?> _curtain = ValueNotifier(null);

  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  double _positionMs = 0;
  int _next = 0; // primeira entrada ainda não aplicada
  bool _playing = false;
  bool _disposed = false;

  /// 1.0 = o tempo do timemap. Não é usado quando [clock] está definido (a
  /// fonte externa já dá a posição musical).
  double speed = 1.0;

  /// Fonte de posição plugável (C01): `null` (padrão) mantém o `Ticker`
  /// somando `delta * speed`, o comportamento de sempre. Definida, o player
  /// passa a ler a posição daqui a cada tick — ver RELÓGIO PLUGÁVEL no
  /// cabeçalho do arquivo.
  PlaybackClock? clock;

  /// A haste de virada em [position]; passe a `ScoreView.curtain`.
  ValueListenable<SweepCurtain?> get curtain => _curtain;

  /// Índice, em [measures], do compasso tocando agora.
  ValueListenable<int> get currentMeasureIndex => _measureIndex;

  /// O último `tempo` do timemap até a posição (`null` se não houver).
  ValueListenable<double?> get tempo => _tempo;

  /// Compassos em ordem de execução.
  List<MeasureInfo> get measures => timeline.measures;

  Duration get position => Duration(microseconds: (_positionMs * 1000).round());
  Duration get duration =>
      Duration(microseconds: (timeline.durationMs * 1000).round());
  bool get isPlaying => _playing;

  Duration get _maxSweepDuration =>
      maxSweepDuration ??
      ((view?.isAttached ?? false)
          ? view!.maxSweepDuration
          : kDefaultMaxSweepDuration);

  double get _barWidthValue =>
      barWidth ??
      ((view?.isAttached ?? false)
          ? view!.barWidth
          : (_defaultBar ??= defaultBarWidth(document)));
  double? _defaultBar;

  // -------------------------------------------------------------------------
  // Transporte
  // -------------------------------------------------------------------------

  void play() {
    if (_disposed || _playing) {
      return;
    }
    if (_positionMs >= timeline.durationMs) {
      seek(Duration.zero);
    }
    _playing = true;
    _lastElapsed = Duration.zero;
    (_ticker ??= Ticker(_onTick, debugLabel: 'ScorePlayer')).start();
  }

  void pause() {
    if (!_playing) {
      return;
    }
    _playing = false;
    _ticker?.stop();
  }

  void _onTick(Duration elapsed) {
    final c = clock;
    if (c != null) {
      final ms = c.positionMs;
      if (ms > _positionMs) {
        _advanceToMs(ms.clamp(0.0, timeline.durationMs));
      } else if (_positionMs - ms > _kClockSeekToleranceMs) {
        seek(Duration(microseconds: (ms * 1000).round()));
      }
      if (_positionMs >= timeline.durationMs) {
        pause();
      }
      return;
    }
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    advance(Duration(microseconds: (delta.inMicroseconds * speed).round()));
    if (_positionMs >= timeline.durationMs) {
      pause();
    }
  }

  /// Avança a posição em [musical] (já multiplicado por `speed`) e aplica
  /// **todas** as entradas ultrapassadas. É o que o `Ticker` chama; o teste
  /// com relógio simulado também.
  void advance(Duration musical) {
    if (_disposed || musical <= Duration.zero) {
      return;
    }
    _advanceToMs(
      (_positionMs + musical.inMicroseconds / 1000.0).clamp(
        0.0,
        timeline.durationMs,
      ),
    );
  }

  void _advanceToMs(double ms) {
    _positionMs = ms;
    final entries = timeline.entries;
    while (_next < entries.length && entries[_next].tstamp <= ms) {
      _apply(entries[_next]);
      _next++;
    }
    _publish();
  }

  void _apply(TimemapEntry e) {
    for (final id in e.off) {
      controller.release(id);
    }
    if (e.on.isNotEmpty) {
      controller.highlightAll(
        e.on,
        color: highlightColor,
        hold: _kForever,
        release: release,
      );
    }
    if (e.tempo != null) {
      _tempo.value = e.tempo;
    }
    onEntry?.call(e);
  }

  /// Vai para [position], recalculando o estado do zero: nenhum destaque
  /// "preso" de antes.
  void seek(Duration position) {
    if (_disposed) {
      return;
    }
    final ms = (position.inMicroseconds / 1000.0).clamp(
      0.0,
      timeline.durationMs,
    );
    _positionMs = ms;
    controller.clearHighlights();
    final entries = timeline.entries;
    final active = <String>{};
    double? tempo;
    var i = 0;
    while (i < entries.length && entries[i].tstamp <= ms) {
      final e = entries[i];
      active.removeAll(e.off);
      active.addAll(e.on);
      tempo = e.tempo ?? tempo;
      i++;
    }
    _next = i;
    _tempo.value = tempo;
    if (active.isNotEmpty) {
      controller.highlightAll(
        active,
        color: highlightColor,
        hold: _kForever,
        release: release,
      );
    }
    _publish(seeking: true);
  }

  /// Vai para o instante em que [id] (compasso, nota, ou id expandido) toca,
  /// como [seek] (E02c). Uso típico:
  /// `ScorePageView(onElementTap: (id) => player.seekToElement(id))`.
  ///
  /// [id] repetido mais de uma vez: sem [pass], a política é **a mesma
  /// passagem em que a posição atual está, senão a 1ª** (D-TOQUE, decisão do
  /// usuário em 2026-09-22). Um `pass:` explícito sempre ganha da política.
  ///
  /// Devolve `false`, sem mexer na posição nem nos destaques, se [id] não
  /// resolve a nada tocado (id desconhecido, ou sem timemap) ou se [pass] foi
  /// pedido e essa passagem não existe.
  bool seekToElement(String id, {int? pass}) {
    if (_disposed) {
      return false;
    }
    final onsets = timeline.onsetsOf(id);
    if (onsets.isEmpty) {
      return false;
    }
    if (pass != null) {
      for (final onset in onsets) {
        if (onset.pass == pass) {
          seek(Duration(milliseconds: onset.ms.round()));
          return true;
        }
      }
      return false;
    }
    final currentPass = timeline.measures.isEmpty
        ? 1
        : timeline.measures[timeline.measureIndexAt(_positionMs)].pass;
    final target = onsets.firstWhere(
      (o) => o.pass == currentPass,
      orElse: () => onsets.first, // a 1ª passagem: onsets está em ordem de
      // tempo, e a passagem 1 sempre toca antes das demais.
    );
    seek(Duration(milliseconds: target.ms.round()));
    return true;
  }

  // -------------------------------------------------------------------------
  // Publicação: compasso, haste, página
  // -------------------------------------------------------------------------

  int _lastScrolledMeasure = -1;

  void _publish({bool force = false, bool seeking = false}) {
    if (timeline.measureCount == 0) {
      return;
    }
    final index = timeline.measureIndexAt(_positionMs);
    if (_measureIndex.value != index) {
      _measureIndex.value = index;
    }
    final v = view;
    final attached = v != null && v.isAttached;
    final continuous = attached && v.mode == ScorePageMode.continuousScroll;
    if (continuous) {
      if (_curtain.value != null) {
        _curtain.value = null;
      }
      if (index != _lastScrolledMeasure || seeking) {
        _lastScrolledMeasure = index;
        v.scrollToId(
          measures[index].id,
          alignment: scrollAlignment,
          duration: seeking ? Duration.zero : scrollDuration,
        );
      }
      return;
    }
    final c = timeline.curtainAt(
      _positionMs,
      maxSweep: _maxSweepDuration,
      barWidth: _barWidthValue,
      singleNoteDelay: singleNoteDelay,
    );
    if (_curtain.value != c) {
      _curtain.value = c;
    }
    if (c == null && attached) {
      final ref = timeline.restViewAt(_positionMs);
      if (v.displayedPage != ref) {
        v.showPage(ref);
      }
    }
  }

  void dispose() {
    _disposed = true;
    _ticker?.dispose();
    _ticker = null;
    _curtain.dispose();
    _measureIndex.dispose();
    _tempo.dispose();
  }
}
