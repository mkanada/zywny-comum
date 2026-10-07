// Medição do tamanho real da partitura na tela. Cada partitura mostrada
// grava uma linha `ZYWNY_TAMANHO` no log do sistema (`adb logcat -s
// flutter`) e no `diag.log` do app (ver `DiagLog`): dá para comparar hino e
// curso no aparelho sem o computador ligado nele. A altura do pentagrama
// (4 espaços) diz o tamanho da nota.

import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:score_bridge/score_bridge.dart';

import 'package:zywny_diag/diag_log.dart';

/// Envolve um `ScoreView` que ocupa a caixa inteira e grava uma medição por
/// (partitura, tamanho de caixa).
class ScoreSizeLog extends StatefulWidget {
  const ScoreSizeLog({
    super.key,
    required this.label,
    required this.document,
    required this.child,
    this.continuous = false,
  });

  /// De onde é a partitura ("hino 001", "exercício l10-ode-juntas").
  final String label;
  final VsbDocument document;
  final Widget child;

  /// `ScorePageMode.continuousScroll`: a página vai pela largura da caixa
  /// (a altura é a soma das páginas), não inteira nela.
  final bool continuous;

  @override
  State<ScoreSizeLog> createState() => _ScoreSizeLogState();
}

class _ScoreSizeLogState extends State<ScoreSizeLog> {
  VsbDocument? _loggedDoc;
  Size? _loggedBox;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        final doc = widget.document;
        if (box.isFinite &&
            (!identical(doc, _loggedDoc) || box != _loggedBox)) {
          _loggedDoc = doc;
          _loggedBox = box;
          final line = scoreSizeLine(
            widget.label,
            doc,
            box,
            MediaQuery.devicePixelRatioOf(context),
            continuous: widget.continuous,
          );
          debugPrint(line);
          DiagLog.log('tamanho', line);
        }
        return widget.child;
      },
    );
  }
}

/// A linha do log: caixa, página, escala (como o `ScoreView` encaixa a
/// página: inteira na caixa, ou pela largura se [continuous]) e a altura do
/// pentagrama em dp e em px reais.
String scoreSizeLine(
  String label,
  VsbDocument doc,
  Size box,
  double dpr, {
  bool continuous = false,
}) {
  final page = doc.pages.first;
  final s = continuous
      ? box.width / page.widthPx
      : min(box.width / page.widthPx, box.height / page.heightPx);
  final staffPage = staffHeightPagePx(doc);
  final staffDp = staffPage == null ? null : staffPage * s;
  String f(double v) => v.toStringAsFixed(1);
  return 'ZYWNY_TAMANHO $label | caixa ${f(box.width)}×${f(box.height)} dp, '
      'dpr ${dpr.toStringAsFixed(3)} | página ${page.widthPx}×${page.heightPx} '
      '(${doc.pages.length} pág.) | escala ${(s * dpr).toStringAsFixed(3)} '
      'px/px | pentagrama '
      '${staffDp == null ? '?' : '${f(staffDp)} dp = ${f(staffDp * dpr)} px'}';
}

/// Altura do pentagrama (8 meios-espaços) em px da primeira página; `null`
/// sem pauta.
double? staffHeightPagePx(VsbDocument doc) {
  final page = doc.pages.first;
  double? found;
  void walk(SceneChild c) {
    if (found != null || c is! SceneNode) return;
    final g = c.staffGeometry;
    if (g != null) {
      found = 8 * g.unit * page.widthPx / page.viewBox.width;
      return;
    }
    c.children.forEach(walk);
  }

  walk(page.root);
  return found;
}
