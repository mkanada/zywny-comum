import 'package:flutter/material.dart';

/// Teclado de piano de 88 teclas (A0=21 .. C8=108) desenhado com
/// `CustomPaint` para o "Monitor MIDI" (M01), acendendo [held].
class PianoKeyboardPainter extends CustomPainter {
  const PianoKeyboardPainter({
    required this.held,
    required this.heldColor,
    this.wrong = const {},
    this.wrongColor = Colors.red,
  });

  final Set<int> held;
  final Color heldColor;

  /// Teclas erradas do modo treino (T02) — pintadas por cima de [held],
  /// já que uma nota errada normalmente também está apertada.
  final Set<int> wrong;
  final Color wrongColor;

  static const int lowestNote = 21; // A0
  static const int highestNote = 108; // C8

  /// Classes de altura (`nota % 12`) das teclas pretas: C#, D#, F#, G#, A#.
  static const Set<int> _blackPitchClasses = {1, 3, 6, 8, 10};

  static bool _isBlack(int note) => _blackPitchClasses.contains(note % 12);

  @override
  void paint(Canvas canvas, Size size) {
    final whiteNotes = [
      for (var n = lowestNote; n <= highestNote; n++)
        if (!_isBlack(n)) n,
    ];
    final whiteWidth = size.width / whiteNotes.length;
    final whiteIndexOf = <int, int>{
      for (var i = 0; i < whiteNotes.length; i++) whiteNotes[i]: i,
    };

    final whitePaint = Paint()..color = Colors.white;
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
          : (held.contains(n) ? heldWhitePaint : whitePaint);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);
    }

    // Pretas por cima, centradas na fronteira com a branca à esquerda — a
    // classe escolhida acima garante que essa vizinha é sempre branca.
    final blackWidth = whiteWidth * 0.6;
    final blackHeight = size.height * 0.62;
    final blackPaint = Paint()..color = Colors.black87;
    final heldBlackPaint = Paint()..color = heldColor;
    final wrongBlackPaint = Paint()..color = wrongColor;
    for (var n = lowestNote; n <= highestNote; n++) {
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
          : (held.contains(n) ? heldBlackPaint : blackPaint);
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PianoKeyboardPainter oldDelegate) =>
      oldDelegate.held != held ||
      oldDelegate.heldColor != heldColor ||
      oldDelegate.wrong != wrong ||
      oldDelegate.wrongColor != wrongColor;
}
