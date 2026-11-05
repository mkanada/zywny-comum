// Nota escondida (L02): o contrato do `ScoreController` — uma notificação por
// chamada, ids expandidos, o acorde que some junto, a precedência sobre cor
// fixa e destaque, e o que não muda sem um documento.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

const _transparent = ui.Color(0x00000000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VsbDocument doc;
  late ScoreController controller;
  late int notifications;

  setUp(() {
    doc = VsbDocument.fromBytes(
      File('test/fixtures/sumico/h010.vsb').readAsBytesSync(),
    );
    controller = ScoreController(document: doc);
    notifications = 0;
    controller.addListener(() => notifications++);
  });

  tearDown(() => controller.dispose());

  test('setHidden: uma notificação, nota e acorde transparentes', () {
    controller.setHidden({'x1848jna', 'z1oagi0k', 'r10709ff'});
    expect(notifications, 1);
    expect(controller.hiddenIds, {'x1848jna', 'z1oagi0k', 'r10709ff'});
    expect(controller.colors['x1848jna'], _transparent);
    expect(controller.colors['r10709ff'], _transparent);
    // O acorde `yy2zfkq` (as duas notas dele) leva a haste e o colchete.
    expect(controller.colors['yy2zfkq'], _transparent);
    expect(controller.isHidden('yy2zfkq'), isFalse, reason: 'só notas são H');
  });

  test('acorde com uma nota visível não fica transparente', () {
    controller.setHidden({'x1848jna'});
    expect(controller.colors.containsKey('yy2zfkq'), isFalse);
    controller.setHidden({'x1848jna', 'z1oagi0k'});
    expect(controller.colors['yy2zfkq'], _transparent);
    controller.reveal('z1oagi0k');
    expect(controller.colors.containsKey('yy2zfkq'), isFalse);
    expect(controller.colors['x1848jna'], _transparent);
  });

  test('reveal, clearHidden e setHidden igual não notificam à toa', () {
    controller.setHidden({'r10709ff'});
    notifications = 0;
    controller.setHidden({'r10709ff'});
    controller.reveal('nc27kmr'); // não está escondida
    controller.reveal('id-que-nao-existe');
    expect(notifications, 0);

    controller.reveal('r10709ff');
    expect(notifications, 1);
    expect(controller.isHidden('r10709ff'), isFalse);
    expect(controller.colors, isEmpty);

    controller.clearHidden();
    expect(notifications, 1, reason: 'já estava vazio');
  });

  test('id expandido (-rend<N>) resolve ao da cena; id que não existe cai fora', () {
    controller.setHidden({'r10709ff-rend2', 'xxxxxxx'});
    expect(controller.hiddenIds, {'r10709ff'});
    expect(controller.isHidden('r10709ff-rend3'), isTrue);
    controller.reveal('r10709ff-rend2');
    expect(controller.hiddenIds, isEmpty);
  });

  test('setHidden troca o conjunto: o que saiu volta, o que entrou some', () {
    controller.setHidden({'r10709ff', 'qyrisol'});
    controller.setHidden({'qyrisol', 'nc27kmr'});
    expect(controller.hiddenIds, {'qyrisol', 'nc27kmr'});
    expect(controller.colors.containsKey('r10709ff'), isFalse);
    expect(controller.colors['nc27kmr'], _transparent);
  });

  test('uma cor fixa não revela a nota; vale ao revelar', () {
    controller.setHidden({'r10709ff'});
    controller.setColor('r10709ff', const ui.Color(0xFF00AA00));
    expect(controller.colors['r10709ff'], _transparent);
    controller.reveal('r10709ff');
    expect(controller.colors['r10709ff'], const ui.Color(0xFF00AA00));

    controller.setHidden({'r10709ff'});
    controller.clearColor('r10709ff');
    expect(controller.colors['r10709ff'], _transparent);
    controller.reveal('r10709ff');
    expect(controller.colors, isEmpty);
  });

  test('clearAll não revela nada; clearHidden revela', () {
    controller.setHidden({'r10709ff'});
    controller.setColor('qyrisol', const ui.Color(0xFF00AA00));
    controller.clearAll();
    expect(controller.hiddenIds, {'r10709ff'});
    expect(controller.colors, {'r10709ff': _transparent});
    controller.clearHidden();
    expect(controller.colors, isEmpty);
  });

  test('highlight em nota escondida é ignorado; em acorde escondido também', () {
    controller.setHidden({'r10709ff'});
    controller.highlight('r10709ff');
    expect(controller.isHighlighted('r10709ff'), isFalse);
    expect(controller.haloColors, isEmpty);
    expect(controller.colors['r10709ff'], _transparent);
  });

  test('esconder uma nota em destaque tira a cor e o halo dela', () {
    controller.highlight('r10709ff', hold: const Duration(seconds: 5));
    expect(controller.haloColors, contains('r10709ff'));
    controller.setHidden({'r10709ff'});
    expect(controller.colors['r10709ff'], _transparent);
    expect(controller.haloColors, isEmpty);
    controller.reveal('r10709ff');
    controller.clearAll();
  });

  test('hiddenShapesOf: vazio sem nada escondido e o mesmo objeto até mudar', () {
    final page = doc.pages[0];
    expect(controller.hiddenShapesOf(page).isEmpty, isTrue);
    controller.setHidden({'m1ujlm1s', 'u1knnyxl', 'w1x5tsbc', 'nc27kmr'});
    final a = controller.hiddenShapesOf(page);
    expect(a.beams.map((b) => b.id), ['l1z05zi4']);
    expect(identical(controller.hiddenLeavesOf(page), a.leaves), isTrue);
    expect(identical(controller.hiddenShapesOf(page), a), isTrue);
    controller.reveal('nc27kmr');
    expect(controller.hiddenShapesOf(page).beams, isEmpty);
  });

  test('trocar de documento esquece o que estava escondido', () {
    controller.setHidden({'r10709ff'});
    final other = VsbDocument.fromBytes(
      File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
    );
    controller.attachDocument(other);
    expect(controller.hiddenIds, isEmpty);
    expect(controller.colors, isEmpty);
  });

  test('sem documento: aceita os ids como estão e não calcula formas', () {
    final bare = ScoreController();
    addTearDown(bare.dispose);
    bare.setHidden({'a', 'b'});
    expect(bare.hiddenIds, {'a', 'b'});
    expect(bare.colors['a'], _transparent);
    expect(bare.hiddenShapesOf(doc.pages[0]).isEmpty, isTrue);
  });
}
