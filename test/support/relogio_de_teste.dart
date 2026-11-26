// O relógio do app nos testes de tela (CT05c): os prazos (o segurar do canto, o
// aviso, os três dedos) andam no ManualClock, e o quadro anda junto.
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_clock/zywny_clock.dart';

/// Um relógio para o teste, começando num dia fixo.
ManualClock relogioDeTeste() => ManualClock(DateTime(2026, 11, 25, 10));

/// Anda o [relogio] e o quadro em [d] juntos. Os avisos do Cubit chegam por um
/// `Stream` (uma microtarefa), então um quadro a mais deixa a árvore refazer o
/// desenho.
Future<void> passar(
  WidgetTester tester,
  ManualClock relogio,
  Duration d,
) async {
  relogio.advance(d);
  await tester.pump(d);
  await tester.pump();
}
