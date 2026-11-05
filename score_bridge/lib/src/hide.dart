// Nota escondida (L02): o que a cena apaga quando um conjunto de notas some.
// Porta das regras 1-3 da §11 de docs/formato/especificacao-v1.md; a referência
// executável é compare/scripts/hide_ref.py (`hidden_shapes`) do bridge, e os
// vetores de teste estão em test/fixtures/sumico/vetores.json.
//
// Aqui só mora o **cálculo** (puro, sem Canvas): dado o conjunto `H` de todas as
// notas escondidas, quais notas, nós `chord`, formas de barra e traços de linha
// suplementar deixam de ser pintados. Quem o aplica é o `ScoreController`
// (cor transparente nas notas e acordes) e o `ScorePageView` (as formas
// estáticas, que não têm id, saem da segmentação).
library;

import 'dart:collection';

import 'model.dart';

/// Folga horizontal entre o traço e a cabeça/pausa que ele cobre (regra 3), em
/// unidades de viewBox.
const double _headSlack = 1.0;

/// Primeira classe de um nó (`"ledgerLines above"` → `"ledgerLines"`).
String _kind(SceneNode node) {
  final name = node.className;
  final space = name.indexOf(' ');
  return space < 0 ? name : name.substring(0, space);
}

bool _hasClass(SceneNode node, String cls) =>
    node.className.split(' ').contains(cls);

/// Uma `beam` de uma página: as formas filhas diretas e as notas que ela cobre.
class HideBeam {
  const HideBeam._(this.id, this.shapes, this.noteIds);

  /// `id` do nó `beam` (pode faltar).
  final String? id;

  /// Formas que não são grupo, filhas **diretas** do `beam` (as barras).
  final List<SceneChild> shapes;

  /// Toda `note` descendente (inclusive dentro de `chord`).
  final List<String> noteIds;
}

/// Um traço de linha suplementar de uma página (regra 3).
class HideLedger {
  const HideLedger._({
    required this.shape,
    required this.staffId,
    required this.above,
    required this.k,
    required this.x1,
    required this.x2,
    required this.owners,
    required this.restOwned,
  });

  /// A forma `p` do traço, na cena.
  final SceneShape shape;

  /// `id` do nó `staff` em que o traço está (`''` se a pauta não tem id).
  final String staffId;

  /// `true` acima da pauta, `false` abaixo.
  final bool above;

  /// Ordem (1ª, 2ª… linha a partir da pauta).
  final int k;
  final double x1;
  final double x2;

  /// Notas a que o traço pertence (mesma pauta de desenho, cabeça coberta em
  /// x, `loc` que alcança a linha).
  final List<String> owners;

  /// Uma pausa deslocada também é dona do traço e nunca é escondida: o traço
  /// fica inteiro.
  final bool restOwned;

  /// O traço some quando toda dona é nota e todas estão em [hidden].
  bool hiddenBy(Set<String> hidden) =>
      owners.isNotEmpty && !restOwned && owners.every(hidden.contains);
}

/// Resultado de [HidePageIndex.shapesFor]: o que some numa página.
class HiddenShapes {
  const HiddenShapes({
    required this.notes,
    required this.chords,
    required this.beams,
    required this.ledgers,
    required this.leaves,
  });

  static final HiddenShapes empty = HiddenShapes(
    notes: const [],
    chords: const [],
    beams: const [],
    ledgers: const [],
    leaves: HashSet<SceneChild>.identity(),
  );

  /// Notas de `H` que estão nesta página (ordenadas).
  final List<String> notes;

  /// Nós `chord` cujas notas estão **todas** em `H` (ordenados).
  final List<String> chords;

  /// `beam` cujas notas estão todas em `H`: o `id` e quantas formas filhas
  /// diretas somem (ordenados por id).
  final List<({String? id, int shapes})> beams;

  /// Traços que somem: `(pauta, lado, ordem, x1, x2)` — `x1`/`x2` na ordem
  /// em que o traço está na cena (arredondados a uma casa), ordenados.
  final List<({String staff, String side, int k, double x1, double x2})>
  ledgers;

  /// As folhas da cena (formas de barra e traços) que deixam de ser pintadas,
  /// comparadas por identidade.
  final Set<SceneChild> leaves;

  bool get isEmpty => leaves.isEmpty;
}

class _NoteRec {
  _NoteRec(this.id, this.node, this.staff);
  final String id;
  final SceneNode node;
  final SceneNode? staff;
}

class _RestRec {
  _RestRec(this.node, this.staff);
  final SceneNode node;
  final SceneNode? staff;
}

final Expando<HidePageIndex> _indexes = Expando('HidePageIndex');

/// Índice de uma página para a nota escondida: pautas, notas (com a pauta de
/// desenho), acordes, barras e traços, montado numa passada. Os traços já
/// trazem as donas, que não dependem de `H`.
class HidePageIndex {
  HidePageIndex._(this.document, this.page) {
    _walk(page.root, null);
    // Cross-staff: o `staffRef` aponta a pauta em que o nó é desenhado.
    SceneNode? resolve(SceneNode? ancestor, String? ref) =>
        ref == null ? ancestor : (staffs[ref] ?? ancestor);
    for (final rec in _noteRecs) {
      final staff = resolve(rec.staff, rec.node.staffRef);
      _notes[rec.id] = _NoteRec(rec.id, rec.node, staff);
    }
    for (final rec in _restRecs) {
      _rests.add(_RestRec(rec.node, resolve(rec.staff, rec.node.staffRef)));
    }
    _buildLedgers();
  }

  /// O índice de [page] (montado uma vez por página e guardado).
  factory HidePageIndex.of(VsbDocument document, ScenePage page) =>
      _indexes[page] ??= HidePageIndex._(document, page);

  final VsbDocument document;
  final ScenePage page;

  /// Nós `staff` por `id`.
  final Map<String, SceneNode> staffs = {};

  /// Notas por `id`, com a pauta em que são desenhadas.
  final Map<String, _NoteRec> _notes = {};

  /// Nós `chord` por `id`, com as notas que eles cobrem.
  final Map<String, List<String>> chords = {};

  final List<HideBeam> beams = [];
  final List<HideLedger> ledgers = [];

  final List<_NoteRec> _noteRecs = [];
  final List<_RestRec> _restRecs = [];
  final List<_RestRec> _rests = [];
  final List<({SceneNode group, SceneNode staff})> _ledgerGroups = [];

  void _walk(SceneNode node, SceneNode? staff) {
    final kind = _kind(node);
    if (kind == 'staff') {
      staff = node;
      final id = node.id;
      if (id != null) staffs[id] = node;
    }
    final id = node.id;
    if (kind == 'note' && id != null) {
      _noteRecs.add(_NoteRec(id, node, staff));
    }
    if ((kind == 'rest' || kind == 'mRest' || kind == 'multiRest') &&
        id != null) {
      _restRecs.add(_RestRec(node, staff));
    }
    if (kind == 'chord' && id != null) {
      chords[id] = noteDescendants(node);
    }
    if (kind == 'beam') {
      beams.add(
        HideBeam._(
          id,
          [
            for (final child in node.children)
              if (child is! SceneNode) child,
          ],
          noteDescendants(node),
        ),
      );
    }
    if (kind == 'ledgerLines' && staff != null) {
      _ledgerGroups.add((group: node, staff: staff));
    }
    for (final child in node.children) {
      if (child is SceneNode) _walk(child, staff);
    }
  }

  /// Os `id` das `note` descendentes de [node], em ordem de documento.
  static List<String> noteDescendants(SceneNode node) {
    final out = <String>[];
    void rec(SceneNode n) {
      for (final child in n.children) {
        if (child is! SceneNode) continue;
        final id = child.id;
        if (_kind(child) == 'note' && id != null) out.add(id);
        rec(child);
      }
    }

    rec(node);
    return out;
  }

  // ---------------------------------------------------------------------
  // Extensões horizontais (regra 3)
  // ---------------------------------------------------------------------

  final Map<String, (double, double)?> _glyphSpan = {};

  /// Menor e maior x dos vértices do contorno do glifo, ou `null`.
  (double, double)? _spanOf(String glyphId) => _glyphSpan.putIfAbsent(glyphId, () {
    final def = document.glyphs[glyphId];
    if (def == null) return null;
    double? lo;
    double? hi;
    for (final path in def.paths) {
      for (var i = 0; i < path.v.length; i += 2) {
        final x = path.v[i];
        if (lo == null || x < lo) lo = x;
        if (hi == null || x > hi) hi = x;
      }
    }
    return lo == null ? null : (lo, hi!);
  });

  /// Os `u` de dentro do nó `notehead` de [note].
  static List<SceneGlyphUse> headGlyphs(SceneNode note) {
    final out = <SceneGlyphUse>[];
    void rec(SceneNode n, bool inHead) {
      inHead = inHead || _hasClass(n, 'notehead');
      for (final child in n.children) {
        if (child is SceneGlyphUse) {
          if (inHead) out.add(child);
        } else if (child is SceneNode) {
          rec(child, inHead);
        }
      }
    }

    rec(note, false);
    return out;
  }

  /// `[xl, xr]` dos `u` dados (contorno × `sx`), ou `null`.
  (double, double)? _extent(Iterable<SceneGlyphUse> uses) {
    double? xl;
    double? xr;
    for (final u in uses) {
      final span = _spanOf(u.glyphId);
      if (span == null) continue;
      final a = u.x + span.$1 * u.sx;
      final b = u.x + span.$2 * u.sx;
      if (xl == null || a < xl) xl = a;
      if (xr == null || b > xr) xr = b;
    }
    return xl == null ? null : (xl, xr!);
  }

  void _buildLedgers() {
    if (_ledgerGroups.isEmpty) return;
    final pitch = document.pitchPos;
    // Candidatas a dona, por pauta de desenho (identidade).
    final notesByStaff = <SceneNode, List<({String id, double xl, double xr, int loc})>>{};
    final restsByStaff = <SceneNode, List<({double xl, double xr, double loc})>>{};
    for (final rec in _notes.values) {
      final staff = rec.staff;
      final event = pitch?.events[rec.id];
      if (staff == null || event == null || !event.isNote) continue;
      final ext = _extent(headGlyphs(rec.node));
      if (ext == null || event.loc == null) continue;
      (notesByStaff[staff] ??= []).add((
        id: rec.id,
        xl: ext.$1,
        xr: ext.$2,
        loc: event.loc!,
      ));
    }
    for (final rec in _rests) {
      final staff = rec.staff;
      final geom = staff?.staffGeometry;
      if (staff == null || geom == null) continue;
      final uses = [
        for (final child in rec.node.children)
          if (child is SceneGlyphUse) child,
      ];
      final ext = _extent(uses);
      if (ext == null || uses.isEmpty) continue;
      final loc =
          2 * (geom.lines - 1) - (uses.first.y - geom.topY) / geom.unit;
      (restsByStaff[staff] ??= []).add((xl: ext.$1, xr: ext.$2, loc: loc));
    }

    for (final (:group, :staff) in _ledgerGroups) {
      final geom = staff.staffGeometry;
      if (geom == null) continue;
      final top = geom.topY;
      final unit = geom.unit;
      final n = geom.lines;
      final bottom = top + 2 * (n - 1) * unit;
      final ownNotes = notesByStaff[staff] ?? const [];
      final ownRests = restsByStaff[staff] ?? const [];
      for (final shape in _leafShapes(group)) {
        if (shape is! ScenePath || shape.paths.isEmpty) continue;
        final v = shape.paths.first.v;
        if (v.length < 3) continue;
        final xa = v[0] < v[2] ? v[0] : v[2];
        final xb = v[0] < v[2] ? v[2] : v[0];
        final y = v[1];
        final above = y < top;
        final k = (above ? (top - y) / (2 * unit) : (y - bottom) / (2 * unit))
            .round();
        bool reaches(num loc, {double eps = 0}) => above
            ? loc >= 2 * (n - 1) + 2 * k - eps
            : loc <= -2 * k + eps;
        final owners = <String>[
          for (final c in ownNotes)
            if (xa - _headSlack <= c.xl &&
                c.xr <= xb + _headSlack &&
                reaches(c.loc))
              c.id,
        ];
        final restOwned = ownRests.any(
          (r) =>
              xa - _headSlack <= r.xl &&
              r.xr <= xb + _headSlack &&
              reaches(r.loc, eps: 0.01),
        );
        ledgers.add(
          HideLedger._(
            shape: shape,
            staffId: staff.id ?? '',
            above: above,
            k: k,
            x1: xa,
            x2: xb,
            owners: owners,
            restOwned: restOwned,
          ),
        );
      }
    }
  }

  static Iterable<SceneChild> _leafShapes(SceneNode node) sync* {
    for (final child in node.children) {
      if (child is SceneNode) {
        yield* _leafShapes(child);
      } else {
        yield child;
      }
    }
  }

  // ---------------------------------------------------------------------
  // Regras 1-3
  // ---------------------------------------------------------------------

  /// O que some nesta página quando as notas [hidden] (`H`: **todas** as
  /// escondidas, não só a coluna atual) somem.
  HiddenShapes shapesFor(Set<String> hidden) {
    if (hidden.isEmpty) return HiddenShapes.empty;
    final leaves = HashSet<SceneChild>.identity();
    final noteIds = [
      for (final id in hidden)
        if (_notes.containsKey(id)) id,
    ]..sort();
    final chordIds = [
      for (final e in chords.entries)
        if (e.value.isNotEmpty && e.value.every(hidden.contains)) e.key,
    ]..sort();
    final beamList = <({String? id, int shapes})>[];
    for (final beam in beams) {
      if (beam.noteIds.isNotEmpty &&
          beam.shapes.isNotEmpty &&
          beam.noteIds.every(hidden.contains)) {
        beamList.add((id: beam.id, shapes: beam.shapes.length));
        leaves.addAll(beam.shapes);
      }
    }
    beamList.sort((a, b) => (a.id ?? '').compareTo(b.id ?? ''));
    final ledgerList =
        <({String staff, String side, int k, double x1, double x2})>[];
    for (final ledger in ledgers) {
      if (!ledger.hiddenBy(hidden)) continue;
      leaves.add(ledger.shape);
      ledgerList.add((
        staff: ledger.staffId,
        side: ledger.above ? 'above' : 'below',
        k: ledger.k,
        x1: double.parse(ledger.x1.toStringAsFixed(1)),
        x2: double.parse(ledger.x2.toStringAsFixed(1)),
      ));
    }
    ledgerList.sort((a, b) {
      var c = a.staff.compareTo(b.staff);
      if (c == 0) c = a.side.compareTo(b.side);
      if (c == 0) c = a.k.compareTo(b.k);
      if (c == 0) c = a.x1.compareTo(b.x1);
      if (c == 0) c = a.x2.compareTo(b.x2);
      return c;
    });
    return HiddenShapes(
      notes: noteIds,
      chords: chordIds,
      beams: beamList,
      ledgers: ledgerList,
      leaves: leaves,
    );
  }

  /// Os ids de nota desta página.
  Iterable<String> get noteIds => _notes.keys;

  /// O nó `staff` em que [noteId] é desenhado (a pauta de desenho, §5.1), ou
  /// `null`.
  SceneNode? staffOfNote(String noteId) => _notes[noteId]?.staff;

  /// O `u`s de cabeça da nota [noteId] (vazio se não existe).
  List<SceneGlyphUse> headsOfNote(String noteId) {
    final rec = _notes[noteId];
    return rec == null ? const [] : headGlyphs(rec.node);
  }
}

extension VsbHiddenShapes on VsbDocument {
  /// O que a cena apaga em [page] quando as notas [hidden] (`H`) somem
  /// (§11, regras 1-3). Ids expandidos (`-rend<N>`) valem: são resolvidos por
  /// [sceneIdOf]. Ids que não estão na página são ignorados.
  HiddenShapes hiddenShapesFor(Set<String> hidden, {PageRef? page}) {
    final ids = <String>{
      for (final id in hidden) ?sceneIdOf(id),
    };
    return HidePageIndex.of(this, pageAt(page ?? const PageRef(0))).shapesFor(ids);
  }
}
