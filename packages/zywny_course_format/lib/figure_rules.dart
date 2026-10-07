import 'course_model.dart';
import 'vocabulary.dart';

/// Quanto uma figura ocupa no **sorteio**, em colcheias: a colcheia sai em
/// par, então ocupa 2.
int figureSlot(Figure f) => f.eighths == 1 ? 2 : f.eighths;

/// Os [allowed] preenchem um compasso de [time] exatamente, com ao menos uma
/// figura que não é pausa?
bool figuresTileMeasure(List<Figure> allowed, String time) {
  final length = measureEighths(time);
  // any[n]: dá para somar n; withNote[n]: dá, usando ao menos uma nota.
  final any = List<bool>.filled(length + 1, false)..[0] = true;
  final withNote = List<bool>.filled(length + 1, false);
  for (var n = 1; n <= length; n++) {
    for (final f in allowed) {
      final slot = figureSlot(f);
      if (slot > n) continue;
      if (any[n - slot]) any[n] = true;
      if (withNote[n - slot] || (!f.rest && any[n - slot])) withNote[n] = true;
    }
  }
  return withNote[length];
}
