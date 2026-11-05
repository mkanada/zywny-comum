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
//
// COMPASSO INTEIRO (T17, G11, regra 8 da §11.2): `shapesFor(..., measures:)` e
// `measureContents` acrescentam o que mais some quando um compasso é escondido
// por inteiro: as pausas de verdade das pautas que têm nota, a tercina e as
// ligaduras que só tocam compassos escondidos. A pausa de compasso que entra no
// lugar é `measureStandInsFor` (stand_in.dart).
library;

import 'dart:collection';

import 'model.dart';

/// Folga horizontal entre o traço e a cabeça/pausa que ele cobre (regra 3), em
/// unidades de viewBox.
const double _headSlack = 1.0;

/// Classes de controle ancorado (regra 8.1): o dono é o conjunto de compassos
/// que eles tocam.
const _controlKinds = {'tie', 'slur', 'phrase', 'arpeg', 'beamSpan'};

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
    required this.restOwners,
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

  /// Pausas deslocadas que também são donas do traço. Uma pausa só é escondida
  /// quando o compasso inteiro some (regra 8.1); fora disso o traço fica.
  final List<String> restOwners;

  /// O traço some quando toda dona está escondida: as notas em [hidden] e as
  /// pausas em [hiddenRests]. Sem dona nenhuma, nunca.
  bool hiddenBy(Set<String> hidden, [Set<String> hiddenRests = const {}]) =>
      (owners.isNotEmpty || restOwners.isNotEmpty) &&
      owners.every(hidden.contains) &&
      restOwners.every(hiddenRests.contains);
}

/// Resultado de [HidePageIndex.shapesFor]: o que some numa página.
class HiddenShapes {
  const HiddenShapes({
    required this.notes,
    required this.chords,
    required this.beams,
    required this.ledgers,
    required this.leaves,
    this.rests = const [],
    this.tuplets = const [],
    this.controls = const [],
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

  /// As folhas da cena (formas de barra, traços e ligaduras) que deixam de ser
  /// pintadas, comparadas por identidade.
  final Set<SceneChild> leaves;

  /// Pausas de verdade que somem com o compasso (regra 8.1), ordenadas. Só com
  /// `measures`.
  final List<String> rests;

  /// Tercinas (`tuplet`) que somem por inteiro: todo o conteúdo some. Só com
  /// `measures`.
  final List<String> tuplets;

  /// Controles ancorados (ligadura, arpejo…) que somem, por `id` ou
  /// `classe@x0,y0,x1,y1`. Só com `measures`.
  final List<String> controls;

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
  String? get id => node.id;
}

class _MeasureRec {
  _MeasureRec(this.node, this.system);
  final SceneNode node;
  final SceneNode? system;

  /// `[x0, x1]` do primeiro traço de linha de cada pauta do compasso (a faixa
  /// que o compasso ocupa), ou `null`.
  late final (double, double)? extent = _extentOf(node);

  static (double, double)? _extentOf(SceneNode measure) {
    double? lo;
    double? hi;
    for (final staff in measure.children) {
      if (staff is! SceneNode || _kind(staff) != 'staff') continue;
      for (final c in staff.children) {
        if (c is ScenePath && c.paths.isNotEmpty) {
          final v = c.paths.first.v;
          if (v.length < 3) break;
          for (final x in [v[0], v[2]]) {
            if (lo == null || x < lo) lo = x;
            if (hi == null || x > hi) hi = x;
          }
          break;
        }
      }
    }
    return lo == null ? null : (lo, hi!);
  }
}

/// O que um compasso escondido leva (regra 8.1): as notas e as pausas de
/// verdade das pautas de desenho que têm nota nele.
typedef MeasureContents = ({List<String> notes, List<String> rests});

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

  /// Compassos por `id` (G11), com o sistema em que estão.
  final Map<String, _MeasureRec> _measureRecs = {};

  /// Os `id` dos compassos desta página, em ordem de documento.
  Iterable<String> get measureIds => _measureRecs.keys;

  /// `id` do compasso de cada nota e pausa.
  final Map<String, String> _measureOf = {};
  final List<SceneNode> _tuplets = [];
  final List<({SceneNode node, SceneNode? system})> _controls = [];
  SceneNode? _system;
  String? _currentMeasure;

  final List<_NoteRec> _noteRecs = [];
  final List<_RestRec> _restRecs = [];
  final List<_RestRec> _rests = [];
  final List<({SceneNode group, SceneNode staff})> _ledgerGroups = [];

  void _walk(SceneNode node, SceneNode? staff, [SceneNode? parent]) {
    final kind = _kind(node);
    if (kind == 'system') _system = node;
    if (kind == 'measure' && node.id != null) {
      _measureRecs[node.id!] = _MeasureRec(node, _system);
      _currentMeasure = node.id;
    }
    if (kind == 'tuplet') _tuplets.add(node);
    if (_controlKinds.contains(kind) &&
        parent != null &&
        (_kind(parent) == 'measure' || _kind(parent) == 'system')) {
      _controls.add((node: node, system: _system));
    }
    if (kind == 'staff') {
      staff = node;
      final id = node.id;
      if (id != null) staffs[id] = node;
    }
    final id = node.id;
    if (kind == 'note' && id != null) {
      _noteRecs.add(_NoteRec(id, node, staff));
      final m = _currentMeasure;
      if (m != null) _measureOf[id] = m;
    }
    if ((kind == 'rest' || kind == 'mRest' || kind == 'multiRest') &&
        id != null) {
      _restRecs.add(_RestRec(node, staff));
      final m = _currentMeasure;
      if (m != null) _measureOf[id] = m;
    }
    if (kind == 'chord' && id != null) {
      chords[id] = noteDescendants(node);
    }
    if (kind == 'beam') {
      beams.add(
        HideBeam._(id, [
          for (final child in node.children)
            if (child is! SceneNode) child,
        ], noteDescendants(node)),
      );
    }
    if (kind == 'ledgerLines' && staff != null) {
      _ledgerGroups.add((group: node, staff: staff));
    }
    for (final child in node.children) {
      if (child is SceneNode) _walk(child, staff, node);
    }
  }

  /// Os `id` das `note` e `rest` descendentes de [node] (a nota de dentro de
  /// um `chord` conta), em ordem de documento.
  static List<String> leafIds(SceneNode node) {
    final out = <String>[];
    void rec(SceneNode n) {
      for (final child in n.children) {
        if (child is! SceneNode) continue;
        final id = child.id;
        final kind = _kind(child);
        if ((kind == 'note' || kind == 'rest') && id != null) out.add(id);
        rec(child);
      }
    }

    rec(node);
    return out;
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
  (double, double)? _spanOf(String glyphId) =>
      _glyphSpan.putIfAbsent(glyphId, () {
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
    final notesByStaff =
        <SceneNode, List<({String id, double xl, double xr, int loc})>>{};
    final restsByStaff =
        <SceneNode, List<({String? id, double xl, double xr, double loc})>>{};
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
      final loc = 2 * (geom.lines - 1) - (uses.first.y - geom.topY) / geom.unit;
      (restsByStaff[staff] ??= []).add((
        id: rec.id,
        xl: ext.$1,
        xr: ext.$2,
        loc: loc,
      ));
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
        bool reaches(num loc, {double eps = 0}) =>
            above ? loc >= 2 * (n - 1) + 2 * k - eps : loc <= -2 * k + eps;
        final owners = <String>[
          for (final c in ownNotes)
            if (xa - _headSlack <= c.xl &&
                c.xr <= xb + _headSlack &&
                reaches(c.loc))
              c.id,
        ];
        final restOwners = <String>[
          for (final r in ownRests)
            if (xa - _headSlack <= r.xl &&
                r.xr <= xb + _headSlack &&
                reaches(r.loc, eps: 0.01))
              r.id ?? '',
        ];
        ledgers.add(
          HideLedger._(
            shape: shape,
            staffId: staff.id ?? '',
            above: above,
            k: k,
            x1: xa,
            x2: xb,
            owners: owners,
            restOwners: restOwners,
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

  /// As notas e as pausas de verdade que somem quando os compassos [measures]
  /// são escondidos por inteiro (regra 8.1). Por pauta de desenho: sem nota no
  /// compasso, nada (a pausa que existe fica); com nota, somem as notas e as
  /// pausas que não são de compasso (`mRest`). Ids que não são compasso desta
  /// página são ignorados.
  MeasureContents measureContents(Set<String> measures) {
    final notes = <String>[];
    final rests = <String>[];
    for (final mid in measures) {
      if (!_measureRecs.containsKey(mid)) continue;
      final notesBy = <SceneNode, List<String>>{};
      for (final rec in _notes.values) {
        final staff = rec.staff;
        if (staff != null && _measureOf[rec.id] == mid) {
          (notesBy[staff] ??= []).add(rec.id);
        }
      }
      for (final entry in notesBy.entries) {
        notes.addAll(entry.value);
      }
      for (final rec in _rests) {
        final id = rec.id;
        final staff = rec.staff;
        if (id == null || staff == null || _measureOf[id] != mid) continue;
        if (_kind(rec.node) == 'mRest') continue;
        if (notesBy.containsKey(staff)) rests.add(id);
      }
    }
    notes.sort();
    rests.sort();
    return (notes: notes, rests: rests);
  }

  /// O que some nesta página quando as notas [hidden] (`H`: **todas** as
  /// escondidas, não só a coluna atual) somem. [hiddenRests] são as pausas
  /// de verdade que somem junto (compasso inteiro); [measures] são os
  /// compassos escondidos por inteiro, que acrescentam a tercina e as
  /// ligaduras que só tocam compassos escondidos (regra 8.1). Quem esconde um
  /// compasso passa também `H` e [hiddenRests] de [measureContents].
  HiddenShapes shapesFor(
    Set<String> hidden, {
    Set<String> hiddenRests = const {},
    Set<String> measures = const {},
  }) {
    if (hidden.isEmpty && hiddenRests.isEmpty) return HiddenShapes.empty;
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
      if (!ledger.hiddenBy(hidden, hiddenRests)) continue;
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
    var tupletIds = const <String>[];
    var controlKeys = const <String>[];
    if (measures.isNotEmpty) {
      tupletIds = [
        for (final tuplet in _tuplets)
          if (tuplet.id != null && _tupletHidden(tuplet, hidden, hiddenRests))
            tuplet.id!,
      ]..sort();
      final keys = <String>[];
      for (final (:node, :system) in _controls) {
        if (!_controlHidden(node, system, measures)) continue;
        keys.add(_controlKey(node));
        leaves.addAll(_leafShapes(node));
      }
      controlKeys = keys..sort();
    }
    return HiddenShapes(
      notes: noteIds,
      chords: chordIds,
      beams: beamList,
      ledgers: ledgerList,
      leaves: leaves,
      rests: [
        for (final id in hiddenRests)
          if (_rests.any((r) => r.id == id)) id,
      ]..sort(),
      tuplets: tupletIds,
      controls: controlKeys,
    );
  }

  /// A tercina some quando toda `note` e toda `rest` dentro dela some.
  bool _tupletHidden(
    SceneNode tuplet,
    Set<String> hidden,
    Set<String> hiddenRests,
  ) {
    final ids = leafIds(tuplet);
    return ids.isNotEmpty &&
        ids.every((id) => hidden.contains(id) || hiddenRests.contains(id));
  }

  /// O controle some quando todos os compassos que ele toca (no mesmo
  /// sistema, mais de 1 unidade de sobreposição) estão escondidos.
  bool _controlHidden(
    SceneNode control,
    SceneNode? system,
    Set<String> measures,
  ) {
    final box = control.bbox;
    if (box == null || control.children.isEmpty) return false;
    var touched = 0;
    for (final entry in _measureRecs.entries) {
      final m = entry.value;
      final ext = m.extent;
      if (!identical(m.system, system) || ext == null) continue;
      final overlap =
          (box.right < ext.$2 ? box.right : ext.$2) -
          (box.left > ext.$1 ? box.left : ext.$1);
      if (overlap > _headSlack) {
        touched++;
        if (!measures.contains(entry.key)) return false;
      }
    }
    return touched > 0;
  }

  /// Identifica um controle: o `id`, ou `classe@x0,y0,x1,y1` (uma casa).
  static String _controlKey(SceneNode control) {
    final id = control.id;
    if (id != null) return id;
    final b = control.bbox!;
    String f(double v) => v.toStringAsFixed(1);
    return '${_kind(control)}@${f(b.left)},${f(b.top)},${f(b.right)},${f(b.bottom)}';
  }

  /// `[x0, x1]` em que o Verovio centra a pausa de compasso de [measureId]
  /// (`measure.inner`), ou `null` (compasso de outra página, ou `.vsb` anterior
  /// a G11).
  (double, double)? innerOf(String measureId) =>
      _measureRecs[measureId]?.node.inner;

  /// As pautas de desenho do compasso [measureId] que têm alguma nota nele, na
  /// ordem do documento (regra 8.2: uma pausa de compasso por pauta).
  List<SceneNode> staffsWithNotes(String measureId) {
    final rec = _measureRecs[measureId];
    if (rec == null) return const [];
    final drawn = HashSet<SceneNode>.identity();
    for (final note in _notes.values) {
      if (note.staff != null && _measureOf[note.id] == measureId) {
        drawn.add(note.staff!);
      }
    }
    return [
      for (final child in rec.node.children)
        if (child is SceneNode &&
            _kind(child) == 'staff' &&
            child.id != null &&
            drawn.contains(child))
          child,
    ];
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
  /// Os `id`s de compasso da cena, na ordem em que tocam (`measureOn` do
  /// timemap, sem repetir; ids expandidos `-rend<N>` resolvidos ao da cena).
  /// Vazio sem timemap. O i-ésimo é o compasso `i` (0-based) da peça.
  List<String> get measureIds {
    final out = <String>[];
    final seen = <String>{};
    for (final entry in timemap ?? const <TimemapEntry>[]) {
      final raw = entry.measureOn;
      final id = raw == null ? null : sceneIdOf(raw);
      if (id != null && seen.add(id)) out.add(id);
    }
    return out;
  }

  /// Notas e pausas de verdade que somem com os compassos [measureIds]
  /// (regra 8.1), nas páginas normais ou só em [page]. Ids expandidos valem;
  /// um id que não é compasso da cena é ignorado. `measures` devolve os que
  /// foram achados.
  ({Set<String> notes, Set<String> rests, Set<String> measures}) measureHideFor(
    Set<String> measureIds, {
    PageRef? page,
  }) {
    final ids = <String>{for (final id in measureIds) ?sceneIdOf(id)};
    final notes = <String>{};
    final rests = <String>{};
    final found = <String>{};
    final scenePages = page == null ? pages : [pageAt(page)];
    for (final scenePage in scenePages) {
      final index = HidePageIndex.of(this, scenePage);
      final here = {
        for (final id in ids)
          if (index.measureIds.contains(id)) id,
      };
      if (here.isEmpty) continue;
      found.addAll(here);
      final contents = index.measureContents(here);
      notes.addAll(contents.notes);
      rests.addAll(contents.rests);
    }
    return (notes: notes, rests: rests, measures: found);
  }

  /// O que a cena apaga em [page] quando os compassos [measureIds] são
  /// escondidos por inteiro (§11.2, regra 8.1): notas, acordes, barras, traços,
  /// pausas de verdade, tercinas e ligaduras.
  HiddenShapes hiddenShapesForMeasures(
    Set<String> measureIds, {
    PageRef? page,
  }) {
    final ref = page ?? const PageRef(0);
    final hide = measureHideFor(measureIds, page: ref);
    return HidePageIndex.of(
      this,
      pageAt(ref),
    ).shapesFor(hide.notes, hiddenRests: hide.rests, measures: hide.measures);
  }

  /// O que a cena apaga em [page] quando as notas [hidden] (`H`) somem
  /// (§11, regras 1-3). Ids expandidos (`-rend<N>`) valem: são resolvidos por
  /// [sceneIdOf]. Ids que não estão na página são ignorados.
  HiddenShapes hiddenShapesFor(Set<String> hidden, {PageRef? page}) {
    final ids = <String>{for (final id in hidden) ?sceneIdOf(id)};
    return HidePageIndex.of(
      this,
      pageAt(page ?? const PageRef(0)),
    ).shapesFor(ids);
  }
}
