import 'package:flutter/material.dart';

import '../course/note_names.dart' show NoteNaming, noteLabel, pitchFromMidi;

/// Teclado de piano desenhado com `CustomPaint`: o "Monitor MIDI" (M01) usa
/// com 88 teclas acendendo [held]; a marca `zywny-keyboard` (I05) usa com
/// uma faixa (`lowest`/`highest`), teclas marcadas e nomes.
///
/// [lowest]/[highest] são números MIDI (A0=21 .. C8=108). [marked] pinta as
/// teclas com [markedColor] (por baixo de [held]/[wrong]); com [names], as
/// teclas brancas marcadas ganham o nome ([noteLabel], sem oitava).
class PianoKeyboardPainter extends CustomPainter {
  const PianoKeyboardPainter({
    required this.held,
    required this.heldColor,
    this.wrong = const {},
    this.wrongColor = Colors.red,
    this.lowest = lowestNote,
    this.highest = highestNote,
    this.marked = const {},
    this.markedColor = const Color(0xFF2F5BD3),
    this.names = false,
    this.naming = NoteNaming.latin,
  });

  final Set<int> held;
  final Color heldColor;

  /// Teclas erradas do modo treino (T02) — pintadas por cima de [held],
  /// já que uma nota errada normalmente também está apertada.
  final Set<int> wrong;
  final Color wrongColor;

  static const int lowestNote = 21; // A0
  static const int highestNote = 108; // C8

  /// Primeira e última tecla desenhadas (inclusivas). O monitor chama com o
  /// padrão (88 teclas, sem mudança visível); a lição passa a faixa do autor.
  final int lowest;
  final int highest;

  /// Teclas marcadas da lição (`zywny-keyboard`), com cor própria.
  final Set<int> marked;
  final Color markedColor;

  /// Escreve o nome nas teclas brancas marcadas ([noteLabel]).
  final bool names;

  /// Grafia dos nomes (Dó–Ré–Mi ou C–D–E).
  final NoteNaming naming;

  /// Classes de altura (`nota % 12`) das teclas pretas: C#, D#, F#, G#, A#.
  static const Set<int> _blackPitchClasses = {1, 3, 6, 8, 10};

  static bool _isBlack(int note) => _blackPitchClasses.contains(note % 12);

  @override
  void paint(Canvas canvas, Size size) {
    final lo = lowest <= highest ? lowest : highest;
    final hi = lowest <= highest ? highest : lowest;
    final whiteNotes = [
      for (var n = lo; n <= hi; n++)
        if (!_isBlack(n)) n,
    ];
    if (whiteNotes.isEmpty) return;
    final whiteWidth = size.width / whiteNotes.length;
    final whiteIndexOf = <int, int>{
      for (var i = 0; i < whiteNotes.length; i++) whiteNotes[i]: i,
    };

    final whitePaint = Paint()..color = Colors.white;
    final markedWhitePaint = Paint()..color = markedColor;
    final heldWhitePaint = Paint()..color = heldColor;
    final wrongWhitePaint = Paint()..color = wrongColor;
    final borderPaint = Paint()
      ..color = Colors.black45
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final n in whiteNotes) {
      final rect = Rect.fromLTWH(
        whiteIndexOf[n]! * whiteWidth,
        0,
        whiteWidth,
        size.height,
      );
      final paint = wrong.contains(n)
          ? wrongWhitePaint
          : (held.contains(n)
                ? heldWhitePaint
                : (marked.contains(n) ? markedWhitePaint : whitePaint));
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);
    }

    // Pretas por cima, centradas na fronteira com a branca à esquerda — a
    // classe escolhida acima garante que essa vizinha é sempre branca.
    final blackWidth = whiteWidth * 0.6;
    final blackHeight = size.height * 0.62;
    final blackPaint = Paint()..color = Colors.black87;
    final markedBlackPaint = Paint()..color = markedColor;
    final heldBlackPaint = Paint()..color = heldColor;
    final wrongBlackPaint = Paint()..color = wrongColor;
    for (var n = lo; n <= hi; n++) {
      if (!_isBlack(n)) continue;
      final leftWhiteIndex = whiteIndexOf[n - 1];
      if (leftWhiteIndex == null) continue;
      final centerX = (leftWhiteIndex + 1) * whiteWidth;
      final rect = Rect.fromLTWH(
        centerX - blackWidth / 2,
        0,
        blackWidth,
        blackHeight,
      );
      final paint = wrong.contains(n)
          ? wrongBlackPaint
          : (held.contains(n)
                ? heldBlackPaint
                : (marked.contains(n) ? markedBlackPaint : blackPaint));
      canvas.drawRect(rect, paint);
    }

    if (names) {
      for (final n in whiteNotes) {
        if (!marked.contains(n)) continue;
        final label = noteLabel(pitchFromMidi(n), naming);
        final span = TextSpan(
          text: label,
          style: TextStyle(
            // Branca marcada: texto escuro sobre a cor de marca clara o
            // bastante; com marca escura (padrão), branco para ler.
            color: _onMark(markedColor),
            fontSize: (whiteWidth * 0.32).clamp(8.0, 16.0),
            fontWeight: FontWeight.w600,
          ),
        );
        final painter = TextPainter(
          text: span,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: whiteWidth);
        painter.paint(
          canvas,
          Offset(
            whiteIndexOf[n]! * whiteWidth + (whiteWidth - painter.width) / 2,
            size.height - painter.height - 4,
          ),
        );
      }
    }
  }

  /// Texto legível sobre [markedColor]: branco nas escuras, tinta nas claras.
  static Color _onMark(Color color) {
    final luminance = color.computeLuminance();
    return luminance < 0.4 ? Colors.white : const Color(0xFF1C1D20);
  }

  @override
  bool shouldRepaint(covariant PianoKeyboardPainter oldDelegate) =>
      oldDelegate.held != held ||
      oldDelegate.heldColor != heldColor ||
      oldDelegate.wrong != wrong ||
      oldDelegate.wrongColor != wrongColor ||
      oldDelegate.lowest != lowest ||
      oldDelegate.highest != highest ||
      oldDelegate.marked != marked ||
      oldDelegate.markedColor != markedColor ||
      oldDelegate.names != names ||
      oldDelegate.naming != naming;
}
