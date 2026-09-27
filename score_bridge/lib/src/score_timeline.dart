// Linha do tempo da peça (A05a/A05b): índice de compassos e posição da haste.
//
// Tudo aqui é **função pura** de `(documento, posição)`, sem widget, sem
// `Ticker` e sem relógio: o `ScorePlayer` só empurra a posição para cá. Por
// isso `seek`, `pause` e `speed` funcionam sem código extra — a haste é
// derivada, nunca guardada.
//
// ÍNDICE DE COMPASSOS. `measures` é a ordem de **execução**: um compasso
// repetido aparece uma vez por passagem (E02b). "Em que compasso é ESTE nó"
// sai da **cena**: o nó de classe `measure` que é ancestral do id, num único
// percurso que também numera cada compasso em ordem de documento (para achar
// salto: a ocorrência seguinte não é o próximo compasso dessa ordem). "Que
// OCORRÊNCIA está tocando" sai do timemap: com `measureOn` (E01b), cada
// entrada com `measureOn` abre uma ocorrência; sem ele (`.vsb` de antes de
// E01b), pelas notas de `on`, abrindo uma ocorrência nova quando o par
// (compasso da cena, passagem) muda — os dois caminhos dão a mesma lista nas
// peças do corpus (E02b, critério 1). Ids são sempre resolvidos por
// `VsbDocument.sceneIdOf`/`passOf` (E02a) antes de entrar em `noteIds`, nas
// bboxes ou na comparação de compasso/passagem.
//
// Um salto (ocorrência cujo compasso não é o seguinte, na ordem de
// documento, do compasso da ocorrência anterior) sempre fecha o `_Run`
// corrente, mesmo **na mesma página** — é o que impede a haste (abaixo) de
// tratar esse trecho como uma virada de página comum.
//
// REGRA DA HASTE (decidida com o usuário em 2026-09-21; ver A05b; generalizada
// para saltos em E03b, D-SALTO = haste generalizada). Sejam `A` a página
// corrente, `M` o último compasso da execução nela, `M'` o primeiro compasso
// da **próxima ocorrência na execução** (o `_Run` seguinte — a página
// seguinte numa virada comum, ou o destino do salto numa repetição) e
// `B` a página de `M'`, com `D = min(teto, duração de M / 4)`:
//
//   * `M.start → M.start + D`   entrada: `0 → xInício(M)`
//   * `→ M'.start`              estacionada em `xInício(M)`
//   * `M'.start → + D`          conclusão: `xInício(M) → fim`
//   * antes/depois              repouso
//
// `SweepCurtain.targetPageIndex = B` sempre que `B ≠ A` — inclusive quando
// `B` não é `A + 1` (salto para trás ou para a frente). Sem salto, `B` já é
// `A + 1`, e os valores não mudam nada em relação à regra original. **Sem**
// haste quando `B == A` (salto na mesma página, ex.: Gymnopédie 39 → 1): a
// página já está à mostra, e um aviso visual do salto é do host, fora daqui.
// Desde P04a, `A`/`B` são `PageRef` (`SweepCurtain.sequence`/
// `.targetSequence`): a página revelada por um salto pode ser uma
// alternativa.
//
// Página de **um** compasso com várias notas: a haste acompanha as notas —
// entra assim que a página aparece, fica logo antes da nota atual e, ao
// destacar a nota k, começa a saltar para a k+1 em `min(D, tempo até ela)`
// (nunca chega atrasada). Com **uma** nota só a conclusão começa 0,5 s depois
// do destaque dela.
//
// ROTA DE EXIBIÇÃO (fase P, P04a; regra de P00 "Player (Dart)"). Cada
// ocorrência de compasso tem uma `view` (`PageRef`): a página normal
// (`sequence == null`) ou de alternativa que o player **exibe** nela —
// diferente de `MeasureInfo.page`, que continua sendo sempre a página normal
// (D-ALT-INDICE). Percorrendo as ocorrências em ordem de execução, com a
// view atual `(s, p)`:
//
//   1. 1ª ocorrência: a página normal do compasso.
//   2. Sem salto: a página do compasso **na sequência `s`** (toda sequência
//      vai até o fim da peça, D-ALT-EXTENSAO, então o compasso está lá).
//   3. Salto para `T`, nesta ordem:
//      a. `T` está na página exibida (`page_s(T) == p`) → fica, sem haste.
//      b. `T` é o 1º compasso de alguma página da sequência `s` → essa
//         página.
//      c. `T` é o 1º compasso de alguma página normal → essa página normal.
//      d. Existe uma sequência alternativa que começa em `T` → a página 0
//         dela.
//      e. Caso contrário (`.vsb` antigo, sem `alternates.json`) → `page_s(T)`
//         — o comportamento de antes de P04a (E03).
//
// `ScoreTimeline(document, useAlternates: false)` (ou um documento sem
// `alternates.json`) pula a regra inteira: toda `view` é a página normal, e
// o resultado é **idêntico** ao de antes de P04a (critério 4).
library;

import 'dart:math' as math;

import 'model.dart';
import 'score_view.dart' show SweepCurtain, sweepEndX;

/// Uma ocorrência de compasso na ordem de execução (E02b): um compasso
/// repetido aparece uma vez por passagem.
class MeasureInfo {
  const MeasureInfo({
    required this.id,
    required this.page,
    required this.view,
    required this.isJump,
    required this.pass,
    required this.timemapId,
    required this.noteIds,
    required this.startMs,
    required this.endMs,
  });

  /// `xml:id` do compasso **na cena** (compatível com quem já usa; o mesmo
  /// em todas as ocorrências do mesmo compasso).
  final String id;

  /// Página **normal** onde ele está. Nunca muda de sentido (D-ALT-INDICE):
  /// para a página que o player realmente exibe nesta ocorrência, use
  /// [view].
  final int page;

  /// Página que o player exibe nesta ocorrência (P04a, regra de P00): a
  /// normal (`sequence == null`) ou a de uma sequência alternativa, quando
  /// um salto de repetição levou a ela. `page` continua sendo sempre a
  /// normal.
  final PageRef view;

  /// `true` quando esta ocorrência **não** é a continuação, em ordem de
  /// documento, da ocorrência anterior — um salto de repetição (`false` na
  /// 1ª ocorrência da peça). É o que decide a `view` (regra de P00) e
  /// abre um novo `_Run`/possível haste.
  final bool isJump;

  /// A execução: `1` na primeira vez que o compasso toca.
  final int pass;

  /// O id como está no timemap desta ocorrência (`id`, ou `id-rendN`). Sem
  /// `measureOn` no `.vsb` (antes de E01b), é reconstruído pela convenção do
  /// sufixo (`id` na passagem 1, `id-rendN` depois).
  final String timemapId;

  /// Notas do compasso nesta ocorrência, na ordem do timemap, resolvidas ao
  /// id da cena (E02a).
  final List<String> noteIds;

  /// `tstamp` da primeira nota desta ocorrência.
  final int startMs;

  /// `tstamp` da primeira nota da ocorrência seguinte (o `tstamp` final, na
  /// última).
  final int endMs;

  @override
  String toString() => 'MeasureInfo($id pass$pass p$page $startMs-$endMs)';
}

/// Uma nota (ou acorde) do compasso: o instante e o x da borda esquerda da
/// mais à esquerda, em unidades de viewBox.
class _Onset {
  const _Onset(this.ms, this.x);
  final double ms;
  final double x;
}

class _Measure {
  _Measure(
    this.id,
    this.page,
    this.pass,
    this.timemapId,
    this.view,
    this.isJump,
  );
  final String id;
  final int page;
  final int pass;
  final String timemapId;
  final PageRef view;
  final bool isJump;
  final List<String> noteIds = [];
  final List<_Onset> onsets = [];
  double startMs = 0;
  double endMs = 0;
  double left = 0;

  double get durationMs => endMs - startMs;
}

/// Sequência de ocorrências consecutivas na mesma [view] (P04a), sem salto.
class _Run {
  _Run(this.view, this.first, this.last);
  final PageRef view;
  final int first;
  int last;
}

class ScoreTimeline {
  /// [useAlternates] liga a rota de exibição de P00/P04a. `false` (ou um
  /// documento sem `alternates.json`) mantém o comportamento de antes de
  /// P04a: toda `view` é a página normal — usado no critério de regressão 4.
  ScoreTimeline(this.document, {this.useAlternates = true}) {
    _build();
  }

  final VsbDocument document;
  final bool useAlternates;

  final List<_Measure> _measures = [];
  final List<_Run> _runs = [];
  late final List<MeasureInfo> measures;
  double durationMs = 0;

  /// Entradas do timemap em ordem de `tstamp`.
  late final List<TimemapEntry> entries;

  /// id (nota, ou o próprio compasso) -> id do compasso ancestral na cena.
  final Map<String, String> _measureOfId = {};

  /// Página de cada compasso.
  final Map<String, int> _pageOfMeasure = {};

  /// Ordem de documento de cada compasso (0-based; para achar salto).
  final Map<String, int> _docOrderOfMeasure = {};

  /// `firstMeasureId` de cada página, por sequência (`null` = normais);
  /// monta os passos "b"/"c" da regra de rota (1º compasso de página).
  /// Vazio quando [useAlternates] é `false` ou o documento não tem
  /// alternativas.
  final Map<int?, Map<String, int>> _firstMeasureOfSequence = {};

  /// Compassos em ordem de execução (A05a).
  List<MeasureInfo> get measureInfos => measures;

  int get measureCount => _measures.length;

  void _build() {
    final entriesList = [...?document.timemap]
      ..sort((a, b) => a.tstamp.compareTo(b.tstamp));
    entries = entriesList;
    durationMs = entriesList.isEmpty ? 0 : entriesList.last.tstamp;

    for (final page in document.pages) {
      _collect(page.root, page.index, null);
    }

    final routeAlternates = useAlternates && document.alternates.isNotEmpty;
    if (routeAlternates) {
      _buildFirstMeasureIndex();
    }

    // com measureOn (E01b): cada entrada com measureOn abre uma ocorrência.
    // sem ele (.vsb de antes de E01b): pela 1ª nota de `on` que resolve a um
    // compasso conhecido, abrindo uma ocorrência nova quando o par
    // (compasso, passagem) muda — mesma regra do script de E01a.
    final hasMeasureOn = entriesList.any((e) => e.measureOn != null);

    _Measure? cur;
    String? curKey;

    void openOccurrence(String measureId, int pass, double ms) {
      final timemapId = pass == 1 ? measureId : '$measureId-rend$pass';
      final prev = _measures.isEmpty ? null : _measures.last;
      final isJump =
          prev != null &&
          _docOrderOfMeasure[measureId] != _docOrderOfMeasure[prev.id]! + 1;
      final view = !routeAlternates
          ? PageRef(_pageOfMeasure[measureId]!)
          : prev == null
          ? PageRef(_pageOfMeasure[measureId]!)
          : !isJump
          ? PageRef(
              _pageInView(prev.view.sequence, measureId) ??
                  _pageOfMeasure[measureId]!,
              sequence: prev.view.sequence,
            )
          : _resolveJump(prev.view, measureId);
      cur = _Measure(
        measureId,
        _pageOfMeasure[measureId]!,
        pass,
        timemapId,
        view,
        isJump,
      )..startMs = ms;
      _measures.add(cur!);
      curKey = '$measureId\u0000$pass';
    }

    for (final e in entriesList) {
      if (hasMeasureOn) {
        final mo = e.measureOn;
        if (mo != null) {
          final measureId = document.sceneIdOf(mo);
          if (measureId != null) {
            openOccurrence(measureId, document.passOf(mo), e.tstamp);
          }
        }
      } else {
        for (final id in e.on) {
          final sceneId = document.sceneIdOf(id);
          if (sceneId == null) continue;
          final measureId = _measureOfId[sceneId];
          if (measureId == null) continue;
          final pass = document.passOf(id);
          final key = '$measureId\u0000$pass';
          if (key != curKey) {
            openOccurrence(measureId, pass, e.tstamp);
          }
          break; // só a 1ª nota de 'on' que resolve decide a ocorrência.
        }
      }
      final m = cur;
      if (m == null) {
        continue; // nada tocado ainda, ou id sem correspondente na cena.
      }
      final geometry = document.geometryOf(m.view.sequence);
      final lefts = <_Measure, double>{};
      for (final id in e.on) {
        final sceneId = document.sceneIdOf(id);
        if (sceneId == null) continue;
        if (!m.noteIds.contains(sceneId)) {
          m.noteIds.add(sceneId);
        }
        final ref = geometry.elementOf(sceneId);
        if (ref != null) {
          final prev = lefts[m];
          lefts[m] = prev == null
              ? ref.bbox.left
              : math.min(prev, ref.bbox.left);
        }
      }
      lefts.forEach((mm, x) => mm.onsets.add(_Onset(e.tstamp, x)));
    }

    for (var i = 0; i < _measures.length; i++) {
      final m = _measures[i];
      m.endMs = i + 1 < _measures.length
          ? _measures[i + 1].startMs
          : durationMs;
      m.left =
          document.geometryOf(m.view.sequence).elementOf(m.id)?.bbox.left ?? 0;
      if (m.onsets.isEmpty) {
        m.onsets.add(_Onset(m.startMs, m.left));
      }
      final last = _runs.isEmpty ? null : _runs.last;
      if (last != null && last.view == m.view && !m.isJump) {
        last.last = i;
      } else {
        _runs.add(_Run(m.view, i, i));
      }
    }
    measures = [
      for (final m in _measures)
        MeasureInfo(
          id: m.id,
          page: m.page,
          view: m.view,
          isJump: m.isJump,
          pass: m.pass,
          timemapId: m.timemapId,
          noteIds: List.unmodifiable(m.noteIds),
          startMs: m.startMs.round(),
          endMs: m.endMs.round(),
        ),
    ];
  }

  void _collect(SceneNode node, int page, String? measure) {
    if (node.hidden) {
      return;
    }
    var current = measure;
    if (node.className == 'measure' && node.id != null) {
      current = node.id;
      _pageOfMeasure[node.id!] = page;
      _docOrderOfMeasure.putIfAbsent(node.id!, () => _docOrderOfMeasure.length);
    }
    if (current != null && node.id != null) {
      _measureOfId[node.id!] = current;
    }
    for (final child in node.children) {
      if (child is SceneNode) {
        _collect(child, page, current);
      }
    }
  }

  /// Monta [_firstMeasureOfSequence]: `firstMeasureId` de cada página das
  /// páginas normais (`null`) e de cada sequência alternativa, uma vez.
  void _buildFirstMeasureIndex() {
    final normal = <String, int>{};
    for (final page in document.pages) {
      final id = page.firstMeasureId;
      if (id != null) {
        normal[id] = page.index;
      }
    }
    _firstMeasureOfSequence[null] = normal;
    for (var s = 0; s < document.alternates.length; s++) {
      final pages = document.alternates[s].pages;
      final map = <String, int>{};
      for (var p = 0; p < pages.length; p++) {
        final id = pages[p].firstMeasureId;
        if (id != null) {
          map[id] = p;
        }
      }
      _firstMeasureOfSequence[s] = map;
    }
  }

  /// Página de [measureId] na sequência [sequence] (`null` = normal), ou
  /// `null` se ele não existir nela — "`page_s(T)`" da regra de P00.
  int? _pageInView(int? sequence, String measureId) => sequence == null
      ? _pageOfMeasure[measureId]
      : document.geometryOf(sequence).pageOf(measureId);

  /// Página cujo [ScenePage.firstMeasureId] é [measureId], na sequência
  /// [sequence] (`null` = normal), ou `null` se nenhuma começar nele.
  int? _firstMeasurePage(int? sequence, String measureId) =>
      _firstMeasureOfSequence[sequence]?[measureId];

  /// Resolve a `view` de um salto para [measureId], vindo de [atual] — os
  /// passos "a"-"e" da regra de P00 ("ROTA DE EXIBIÇÃO", no topo do
  /// arquivo).
  PageRef _resolveJump(PageRef atual, String measureId) {
    final s = atual.sequence;
    final pageInS = _pageInView(s, measureId);
    if (pageInS == atual.index) {
      return atual; // a. já está na página exibida.
    }
    final sameSequencePage = _firstMeasurePage(s, measureId);
    if (sameSequencePage != null) {
      return PageRef(sameSequencePage, sequence: s); // b.
    }
    final normalPage = _firstMeasurePage(null, measureId);
    if (normalPage != null) {
      return PageRef(normalPage); // c.
    }
    final altIndex = document.alternates.indexWhere(
      (seq) => seq.start == measureId,
    );
    if (altIndex != -1) {
      return PageRef(0, sequence: altIndex); // d.
    }
    return PageRef(pageInS ?? _pageOfMeasure[measureId]!, sequence: s); // e.
  }

  /// Índices em [measures] das ocorrências de [id]: compasso ou nota, todas
  /// as passagens em que aparece; um id expandido (`-rend<N>`), só a sua
  /// (E02b).
  List<int> occurrencesOf(String id) {
    final sceneId = document.sceneIdOf(id);
    if (sceneId == null) {
      return const [];
    }
    final measureId = _measureOfId[sceneId];
    if (measureId == null) {
      return const [];
    }
    final expanded = id != sceneId;
    final pass = document.passOf(id);
    return [
      for (var i = 0; i < measures.length; i++)
        if (measures[i].id == measureId &&
            (!expanded || measures[i].pass == pass))
          i,
    ];
  }

  /// Instante(s) em que [id] toca, em ordem de tempo: um item por passagem
  /// em que o elemento (compasso, nota, ou id expandido) é tocado. Um id
  /// expandido (`-rend<N>`) devolve só o instante da sua passagem (E02c).
  ///
  /// Vazio se [id] não resolve a nada na cena, ou se não há timemap.
  List<({int pass, double ms})> onsetsOf(String id) {
    final sceneId = document.sceneIdOf(id);
    if (sceneId == null) {
      return const [];
    }
    final expanded = id != sceneId;
    if (_measureOfId[sceneId] == sceneId) {
      // é o próprio compasso: o instante de cada ocorrência é o startMs
      // dela (já resolvido pelas regras de occurrencesOf).
      return [
        for (final i in occurrencesOf(id))
          (pass: measures[i].pass, ms: measures[i].startMs.toDouble()),
      ];
    }
    // nota (ou outro elemento com onset no timemap): o instante de cada
    // passagem é o tstamp da entrada cujo `on` traz o id dela, com o
    // sufixo daquela passagem (ou sem sufixo, na passagem 1).
    final requestedPass = document.passOf(id);
    final result = <({int pass, double ms})>[];
    for (final e in entries) {
      for (final onId in e.on) {
        if (document.sceneIdOf(onId) != sceneId) {
          continue;
        }
        final pass = document.passOf(onId);
        if (expanded && pass != requestedPass) {
          continue;
        }
        result.add((pass: pass, ms: e.tstamp));
      }
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Consultas por posição
  // -------------------------------------------------------------------------

  /// Índice, em [measures], do compasso tocando em [ms] (0 antes do primeiro).
  int measureIndexAt(double ms) {
    var lo = 0;
    var hi = _measures.length - 1;
    var found = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_measures[mid].startMs <= ms) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// A página **normal** que fica em repouso em [ms] quando não há haste: a
  /// do compasso corrente. Continua sempre normal (D-ALT-INDICE); para a que
  /// o player realmente exibe, use [restViewAt].
  int restPageAt(double ms) =>
      _measures.isEmpty ? 0 : _measures[measureIndexAt(ms)].page;

  /// A `view` (P04a) que fica em repouso em [ms] quando não há haste: a do
  /// compasso corrente.
  PageRef restViewAt(double ms) =>
      _measures.isEmpty ? const PageRef(0) : _measures[measureIndexAt(ms)].view;

  double _dOf(_Measure m, double maxSweepMs) =>
      math.min(maxSweepMs, m.durationMs / 4);

  /// A haste em [ms], ou `null` (repouso). Função pura da posição.
  ///
  /// [maxSweep] é o teto de cada movimento (`ScoreView.maxSweepDuration`) e
  /// [barWidth] a largura da haste em unidades de viewBox (para o "fim").
  SweepCurtain? curtainAt(
    double ms, {
    required Duration maxSweep,
    required double barWidth,
    Duration singleNoteDelay = const Duration(milliseconds: 500),
  }) {
    final maxMs = maxSweep.inMicroseconds / 1000.0;
    for (var r = 0; r + 1 < _runs.length; r++) {
      final run = _runs[r];
      final next = _runs[r + 1];
      if (next.view == run.view) {
        continue; // salto na mesma view: nada para revelar (fora de
        // escopo de E03a/E03b — aviso visual é do host)
      }
      final m = _measures[run.last];
      final page = document.pageAt(run.view);
      final end = sweepEndX(page, barWidth);
      final d = _dOf(m, maxMs);
      final count = run.last - run.first + 1;
      final edge = count > 1
          ? _multiMeasureEdge(ms, m, d, end)
          : _singleMeasureEdge(
              ms,
              run,
              r > 0 ? _runs[r - 1] : null,
              m,
              d,
              end,
              maxMs,
              singleNoteDelay.inMicroseconds / 1000.0,
            );
      if (edge != null) {
        return SweepCurtain(
          pageIndex: run.view.index,
          edgeX: edge,
          sequence: run.view.sequence,
          targetPageIndex: next.view.index,
          targetSequence: next.view.sequence,
        );
      }
    }
    return null;
  }

  double? _multiMeasureEdge(double ms, _Measure m, double d, double end) {
    final s = m.startMs;
    final e = m.endMs;
    if (ms < s || ms >= e + d) {
      return null;
    }
    if (ms < s + d) {
      return m.left * ((ms - s) / d);
    }
    if (ms < e) {
      return m.left;
    }
    return m.left + (end - m.left) * ((ms - e) / d);
  }

  double? _singleMeasureEdge(
    double ms,
    _Run run,
    _Run? prev,
    _Measure m,
    double d,
    double end,
    double maxMs,
    double delayMs,
  ) {
    final onsets = m.onsets;
    final first = _measures[run.first];
    // Quando a página aparece: 0 na primeira; senão, quando termina a
    // conclusão da virada anterior.
    var appear = 0.0;
    if (prev != null) {
      appear = first.startMs;
      if (prev.view != run.view) {
        appear += _dOf(_measures[prev.last], maxMs);
      }
    }
    final single = onsets.length == 1;
    // Uma nota só: a conclusão começa `delayMs` após o destaque — mas não
    // antes de a haste ter terminado de entrar (se a página aparece depois
    // disso, a haste não pode surgir já no meio da conclusão).
    final concStart = single
        ? math.min(math.max(onsets.first.ms + delayMs, appear + d), m.endMs)
        : m.endMs;
    if (ms < appear || ms >= concStart + d) {
      return null;
    }
    // Posição-alvo antes da entrada e do fecho.
    var pos = onsets.first.x;
    for (var k = 1; k < onsets.length; k++) {
      final from = onsets[k - 1];
      final to = onsets[k];
      final dur = math.min(d, to.ms - from.ms);
      if (ms >= from.ms + dur) {
        pos = to.x;
      } else if (ms >= from.ms) {
        pos = from.x + (to.x - from.x) * (dur == 0 ? 1 : (ms - from.ms) / dur);
        break;
      } else {
        break;
      }
    }
    if (ms >= concStart) {
      return pos + (end - pos) * ((ms - concStart) / d);
    }
    if (ms < appear + d) {
      return pos * ((ms - appear) / d);
    }
    return pos;
  }
}
