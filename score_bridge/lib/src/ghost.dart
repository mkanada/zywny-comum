// Nota fantasma (G03-G05): onde uma tecla MIDI qualquer ficaria escrita na
// coluna de um evento esperado. Porta da §10 de docs/formato/especificacao-v1.md
// (a referência executável é compare/scripts/ghost_ref.py do bridge, e os
// vetores de teste estão em test/fixtures/fantasma/vetores.json).
library;

import 'model.dart';

const List<int> _semitones = [0, 2, 4, 5, 7, 9, 11];
const String _letters = 'cdefgab';
const int _maxLedgers = 4;

/// Folga entre acidente e cabeça, em `unit` (medida em G04d; §10 passo 8).
const double _accidentalGapPerUnit = 0.5;

/// Convenção visual do marcador de oitava (§10 passo 8): linha de base a
/// `3 unit` acima / `5 unit` abaixo da peça mais extrema.
const double _octaveAboveUnits = 3;
const double _octaveBelowUnits = 5;

const Map<int, String> _accidentalGlyph = {
  1: 'E262',
  -1: 'E260',
  0: 'E261',
  2: 'E263',
  -2: 'E264',
};

/// Um glifo posicionado da fantasma, no referencial de conteúdo da página
/// (§5.1 `bbox`; o painter soma `origin` da página como para o resto).
class GhostGlyph {
  /// Chave em [VsbDocument.glyphs] (`"<fonte>:E0A4"`).
  final String glyphId;
  final double x;
  final double y;
  final double sx;
  final double sy;

  const GhostGlyph({
    required this.glyphId,
    required this.x,
    required this.y,
    required this.sx,
    required this.sy,
  });
}

/// Linha suplementar da fantasma.
class GhostLedger {
  final double y;
  final double x1;
  final double x2;
  final double thickness;

  const GhostLedger({
    required this.y,
    required this.x1,
    required this.x2,
    required this.thickness,
  });
}

/// A fantasma de uma tecla errada.
class GhostNote {
  /// Tecla MIDI tocada.
  final int key;

  /// Página em que foi calculada (onde está o evento esperado).
  final PageRef page;

  /// `id` do nó `staff` onde ela é desenhada (a pauta do alvo).
  final String? staffId;

  /// Posição vertical final (depois do deslocamento de oitava) e antes dele.
  final int loc;
  final int locRaw;

  /// 0 = sem marcador de oitava; 1 = 8va/8vb; 2 = 15ma/15mb.
  final int octaveShift;

  /// Grafia escolhida: letra minúscula, oitava escrita e alteração (−1, 0, +1).
  final String pname;
  final int octave;
  final int alter;

  /// Id notado do evento esperado em cuja coluna ela foi posta.
  final String targetId;

  final GhostGlyph head;
  final double headWidth;

  /// `null` quando o acidente não é necessário (armadura/acidentes em vigor).
  final GhostGlyph? accidental;
  final List<GhostLedger> ledgers;
  final GhostGlyph? octaveMarker;

  const GhostNote({
    required this.key,
    required this.page,
    required this.staffId,
    required this.loc,
    required this.locRaw,
    required this.octaveShift,
    required this.pname,
    required this.octave,
    required this.alter,
    required this.targetId,
    required this.head,
    required this.headWidth,
    required this.accidental,
    required this.ledgers,
    required this.octaveMarker,
  });

  /// A mesma fantasma deslocada [dx] (unidades de conteúdo da página) na
  /// horizontal — para a nota tocada antes (`dx < 0`) ou depois (`dx > 0`) do
  /// tempo, ao lado da coluna do evento esperado em vez de em cima dela.
  GhostNote shifted(double dx) {
    if (dx == 0) return this;
    GhostGlyph move(GhostGlyph g) =>
        GhostGlyph(glyphId: g.glyphId, x: g.x + dx, y: g.y, sx: g.sx, sy: g.sy);
    return GhostNote(
      key: key,
      page: page,
      staffId: staffId,
      loc: loc,
      locRaw: locRaw,
      octaveShift: octaveShift,
      pname: pname,
      octave: octave,
      alter: alter,
      targetId: targetId,
      head: move(head),
      headWidth: headWidth,
      accidental: accidental == null ? null : move(accidental!),
      ledgers: [
        for (final l in ledgers)
          GhostLedger(
            y: l.y,
            x1: l.x1 + dx,
            x2: l.x2 + dx,
            thickness: l.thickness,
          ),
      ],
      octaveMarker: octaveMarker == null ? null : move(octaveMarker!),
    );
  }
}

class _Located {
  _Located(this.node, this.staff);
  final SceneNode node;
  final SceneNode? staff;
}

/// Índice `id → (nó, pauta ancestral)` e `id da pauta → nó` de uma página,
/// montado numa passada.
class _GhostPageIndex {
  _GhostPageIndex(ScenePage page) {
    _walk(page.root, null);
  }

  final Map<String, _Located> nodes = {};
  final Map<String, SceneNode> staves = {};

  void _walk(SceneNode node, SceneNode? staff) {
    if (node.className.split(' ').first == 'staff') {
      staff = node;
      final id = node.id;
      if (id != null) staves[id] = node;
    }
    final id = node.id;
    if (id != null) nodes[id] = _Located(node, staff);
    for (final child in node.children) {
      if (child is SceneNode) _walk(child, staff);
    }
  }
}

final Expando<Map<PageRef, _GhostPageIndex>> _indexes = Expando();

class _Candidate {
  _Candidate({
    required this.id,
    required this.event,
    required this.staff,
    required this.geometry,
    required this.head,
    required this.node,
    required this.written,
    required this.ref,
  });

  final String id;
  final PitchEvent event;
  final SceneNode staff;
  final StaffGeometry geometry;
  final SceneGlyphUse? head;
  final SceneNode node;

  /// Altura escrita (natural + alteração para nota; linha do meio para pausa).
  final int written;

  /// Altura de referência sonora (`written + shift`).
  final int ref;
}

int _midiNatural(int pname, int octave) =>
    12 * (octave + 1) + _semitones[pname - 1];

int _floorDiv(int a, int b) => (a / b).floor();

/// (pname 1..7, oct) da letra natural de uma tecla branca.
(int, int) _naturalOf(int midi) =>
    (_semitones.indexOf(midi % 12) + 1, _floorDiv(midi, 12) - 1);

SceneGlyphUse? _firstGlyph(SceneNode node, {required bool inNotehead}) {
  SceneGlyphUse? rec(SceneNode n, bool inHead) {
    inHead = inHead || n.className.split(' ').contains('notehead');
    for (final child in n.children) {
      if (child is SceneGlyphUse && (inHead || !inNotehead)) return child;
      if (child is SceneNode) {
        final found = rec(child, inHead);
        if (found != null) return found;
      }
    }
    return null;
  }

  return rec(node, false);
}

(int, int, int) _spell(
  int w,
  int written,
  Map<String, int> key,
  (int, int, int)? targetNote,
) {
  if (w == written && targetNote != null) return targetNote;
  if (_semitones.contains(w % 12)) {
    final (p, o) = _naturalOf(w);
    return (p, o, 0);
  }
  final hasSharp = key.values.any((v) => v > 0);
  final hasFlat = key.values.any((v) => v < 0);
  final bool sharp;
  if (hasSharp && !hasFlat) {
    sharp = true;
  } else if (hasFlat && !hasSharp) {
    sharp = false;
  } else {
    sharp = w > written;
  }
  if (sharp) {
    final (p, o) = _naturalOf(w - 1);
    return (p, o, 1);
  }
  final (p, o) = _naturalOf(w + 1);
  return (p, o, -1);
}

int _ledgerCount(int loc, int lines) {
  final top = 2 * (lines - 1);
  if (loc > top) return (loc - top) ~/ 2;
  if (loc < 0) return (-loc) ~/ 2;
  return 0;
}

extension VsbGhostNotes on VsbDocument {
  /// Uma [GhostNote] por tecla de [wrongKeys] (em ordem crescente de tecla),
  /// na coluna dos eventos esperados [expectedIds] — notas e/ou pausas; pode
  /// ser id expandido do timemap (`-rend<N>`), que é resolvido por
  /// [sceneIdOf]. Passe **todas** as notas de um acorde esperado: a colisão
  /// (D-FANT-COLISAO) precisa conhecê-las.
  ///
  /// [page] é onde procurar os nós (padrão: a página normal que contém o
  /// primeiro id esperado). Vazia sem `pitchpos.json`, sem candidato
  /// resolvível ou sem geometria de pauta (`.vsb` anterior à nota fantasma).
  ///
  /// Especificação: §10 de docs/formato/especificacao-v1.md.
  List<GhostNote> ghostsFor({
    required List<String> expectedIds,
    required List<int> wrongKeys,
    PageRef? page,
  }) {
    final pitchPos = this.pitchPos;
    if (pitchPos == null || expectedIds.isEmpty || wrongKeys.isEmpty) {
      return const [];
    }
    final notated = <String>[for (final id in expectedIds) ?sceneIdOf(id)];
    if (notated.isEmpty) return const [];

    final (ref, index) = _ghostIndexFor(notated, page);
    if (index == null) return const [];

    final cands = <_Candidate>[];
    for (final id in notated.toSet()) {
      final event = pitchPos.events[id];
      final located = index.nodes[id];
      if (event == null || located == null) continue;
      final staff = located.node.staffRef != null
          ? index.staves[located.node.staffRef]
          : located.staff;
      final geometry = staff?.staffGeometry;
      if (staff == null || geometry == null) continue;
      final head = _firstGlyph(located.node, inNotehead: event.isNote);
      final int written;
      if (event.isNote) {
        written =
            _midiNatural(_letters.indexOf(event.pname!) + 1, event.octave!) +
            event.alter!;
      } else {
        final pos = (geometry.lines - 1) - event.clefOffset + 28;
        written = _midiNatural(pos % 7 + 1, _floorDiv(pos, 7));
      }
      cands.add(
        _Candidate(
          id: id,
          event: event,
          staff: staff,
          geometry: geometry,
          head: head,
          node: located.node,
          written: written,
          ref: written + event.shift,
        ),
      );
    }
    if (cands.isEmpty) return const [];

    // Candidatos por pauta (id do nó quando há, senão identidade).
    final groups = <Object, List<_Candidate>>{};
    for (final c in cands) {
      (groups[c.staff.id ?? c.staff] ??= []).add(c);
    }
    final single = groups.length == 1;

    final font = glyphs.keys.first.split(':').first;
    double glyphWidth(String glyphId, double sx) =>
        glyphs[glyphId]!.bbox.width / 10.0 * sx;

    final placed = <({String? staff, int loc, double x, double width})>[];
    final out = <GhostNote>[];
    for (final k in (List.of(wrongKeys)..sort())) {
      // 1. proposta por pauta (G06): alvo da pauta (menor |k - ref|; empate,
      //    o de cima), com grafia/loc/suplementares do contexto dessa pauta;
      //    vence a pauta com menos suplementares brutas (antes de 8va).
      //    Desempates: menor |k - ref|, depois maior ref.
      ({_Candidate t, int pname, int octv, int alt, int loc, int led})? best;
      for (final members in groups.values) {
        var t = members.first;
        for (final c in members.skip(1)) {
          final dc = (k - c.ref).abs();
          final dt = (k - t.ref).abs();
          if (dc < dt || (dc == dt && c.ref > t.ref)) t = c;
        }
        final ev = t.event;
        (int, int, int)? targetNote;
        if (ev.isNote) {
          targetNote = (_letters.indexOf(ev.pname!) + 1, ev.octave!, ev.alter!);
        }
        final (pname, octv, alt) = _spell(
          k - ev.shift,
          t.written,
          ev.key,
          targetNote,
        );
        final loc = (octv - 4) * 7 + (pname - 1) + ev.clefOffset;
        final led = _ledgerCount(loc, t.geometry.lines);
        if (best == null) {
          best = (t: t, pname: pname, octv: octv, alt: alt, loc: loc, led: led);
          continue;
        }
        final b = best;
        final dn = (k - t.ref).abs();
        final db = (k - b.t.ref).abs();
        if (led < b.led ||
            (led == b.led && (dn < db || (dn == db && t.ref > b.t.ref)))) {
          best = (t: t, pname: pname, octv: octv, alt: alt, loc: loc, led: led);
        }
      }
      final t = best!.t;
      final pname = best.pname;
      final octv = best.octv;
      final alt = best.alt;
      final ev = t.event;
      final lines = t.geometry.lines;
      final top = t.geometry.topY;
      final unit = t.geometry.unit;
      final topLoc = 2 * (lines - 1);
      var loc = best.loc;
      final locRaw = loc;
      // 5. alcance: com pauta única vale a regra integral; entre pautas, só
      //    desloca se o melhor cabimento passar de 4.
      var led = best.led;
      var m = 0;
      if (single || led > _maxLedgers) {
        while (led > _maxLedgers && m < 2) {
          loc = locRaw > topLoc ? loc - 7 : loc + 7;
          m++;
          led = _ledgerCount(loc, lines);
        }
      }
      final up = locRaw > topLoc;
      if (led > _maxLedgers) {
        // Além de duas oitavas: presa em 4 linhas (limitação aceita, §10).
        loc = up ? topLoc + 2 * _maxLedgers : -2 * _maxLedgers;
        led = _maxLedgers;
      }

      // 6. acidente (antes do deslocamento de oitava).
      final letter = _letters[pname - 1];
      final keyAlt = ev.key[letter] ?? 0;
      final inForce = ev.accidentals['$letter$octv'] ?? keyAlt;

      // 7. cabeça e x.
      final u = t.head;
      final gs = (t.geometry.glyphScaleX, t.geometry.glyphScaleY);
      final (sx, sy) = (ev.isNote && u != null) ? (u.sx, u.sy) : gs;
      var x = u?.x ?? t.node.bbox?.left ?? 0;
      final headId = '$font:E0A4';
      final width = glyphWidth(headId, sx);
      final staffId = t.staff.id;
      if (ev.isNote) {
        final reals = <({int loc, double x, double width})>[
          for (final c in cands)
            if (c.event.isNote && identical(c.staff, t.staff) && c.head != null)
              (
                loc: c.event.loc!,
                x: c.head!.x,
                width: glyphWidth(c.head!.glyphId, c.head!.sx),
              ),
        ];
        var moved = true;
        while (moved) {
          moved = false;
          final others = [
            ...reals,
            for (final p in placed)
              if (p.staff == staffId) (loc: p.loc, x: p.x, width: p.width),
          ];
          for (final r in others) {
            if ((loc - r.loc).abs() <= 1 &&
                r.x < x + width &&
                x < r.x + r.width) {
              x += width;
              moved = true;
              break;
            }
          }
        }
      }
      final y = top + (topLoc - loc) * unit;

      GhostGlyph? accidental;
      if (alt != inForce) {
        final id = '$font:${_accidentalGlyph[alt]}';
        accidental = GhostGlyph(
          glyphId: id,
          x: x - _accidentalGapPerUnit * unit - glyphWidth(id, sx),
          y: y,
          sx: sx,
          sy: sy,
        );
      }

      // 8. linhas suplementares.
      final ledgers = <GhostLedger>[];
      if (led > 0) {
        final cue = u != null && sx < gs.$1 * 0.999 && t.geometry.hasLedgerCue;
        final thick = cue
            ? t.geometry.ledgerCueThickness!
            : t.geometry.ledgerThickness;
        final ext = cue
            ? t.geometry.ledgerCueExtension!
            : t.geometry.ledgerExtension;
        for (var j = 1; j <= led; j++) {
          final lloc = loc > topLoc ? topLoc + 2 * j : -2 * j;
          ledgers.add(
            GhostLedger(
              y: top + (topLoc - lloc) * unit,
              x1: x - ext,
              x2: x + width + ext,
              thickness: thick,
            ),
          );
        }
      }

      GhostGlyph? octaveMarker;
      if (m > 0) {
        final code = switch ((up, m)) {
          (true, 1) => 'E511',
          (false, 1) => 'E512',
          (true, _) => 'E515',
          (false, _) => 'E516',
        };
        final id = '$font:$code';
        final extremeY = ledgers.isNotEmpty ? ledgers.last.y : y;
        octaveMarker = GhostGlyph(
          glyphId: id,
          x: x + width / 2 - glyphWidth(id, sx) / 2,
          y: up
              ? extremeY - _octaveAboveUnits * unit
              : extremeY + _octaveBelowUnits * unit,
          sx: sx,
          sy: sy,
        );
      }

      placed.add((staff: staffId, loc: loc, x: x, width: width));
      out.add(
        GhostNote(
          key: k,
          page: ref,
          staffId: staffId,
          loc: loc,
          locRaw: locRaw,
          octaveShift: m,
          pname: letter,
          octave: octv,
          alter: alt,
          targetId: t.id,
          head: GhostGlyph(glyphId: headId, x: x, y: y, sx: sx, sy: sy),
          headWidth: width,
          accidental: accidental,
          ledgers: ledgers,
          octaveMarker: octaveMarker,
        ),
      );
    }
    return out;
  }

  (PageRef, _GhostPageIndex?) _ghostIndexFor(
    List<String> notated,
    PageRef? page,
  ) {
    final cache = _indexes[this] ??= {};
    _GhostPageIndex indexOf(PageRef ref) =>
        cache[ref] ??= _GhostPageIndex(pageAt(ref));
    if (page != null) return (page, indexOf(page));
    for (var i = 0; i < pages.length; i++) {
      final ref = PageRef(i);
      if (indexOf(ref).nodes.containsKey(notated.first)) {
        return (ref, indexOf(ref));
      }
    }
    return (const PageRef(0), null);
  }
}
