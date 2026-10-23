import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_diag/diag_log.dart';

void main() {
  tearDown(DiagLog.reset);

  Future<MemoryDiagStorage> start([MemoryDiagStorage? store]) async {
    final s = store ?? MemoryDiagStorage();
    await DiagLog.init(storage: s, installHandlers: false);
    return s;
  }

  test('antes do init tudo é no-op', () {
    DiagLog.log('x', 'y');
    expect(DiagLog.beginSession('aula', 'a'), isNull);
    expect(DiagLog.collect(), isEmpty);
  });

  test(
    'as linhas vão para a sessão aberta; erro vai também para app',
    () async {
      final store = await start();
      final s = DiagLog.beginSession('exercicio', '34d')!;
      DiagLog.log('nota', 'on 60');
      DiagLog.log('erro', 'quebrou');
      DiagLog.endSession(s);
      DiagLog.log('midi', 'fora da sessão');

      final session = store.read(s.key);
      expect(session, contains('#sessao tipo=exercicio nome="34d"'));
      expect(session, contains('[nota] on 60'));
      expect(session, contains('[erro] quebrou'));
      expect(session, contains('[sessao] fim: exercicio 34d'));
      expect(session, isNot(contains('fora da sessão')));

      final app = store.read('app');
      expect(app, contains('[erro] quebrou'));
      expect(app, contains('fora da sessão'));
      expect(app, isNot(contains('on 60')));
    },
  );

  test('ficam só as duas últimas sessões encerradas', () async {
    final store = await start();
    final keys = <String>[];
    for (final n in ['a', 'b', 'c', 'd']) {
      final s = DiagLog.beginSession('musica', n)!;
      keys.add(s.key);
      DiagLog.log('nota', n);
      DiagLog.endSession(s);
    }
    expect(store.keys().where((k) => k != 'app'), keys.sublist(2));
    final files = DiagLog.collect().map((f) => f.name);
    expect(files, ['app.log', '${keys[2]}.log', '${keys[3]}.log']);
  });

  test(
    'a sessão aberta não conta e a de baixo da pilha volta a receber',
    () async {
      final store = await start();
      final aula = DiagLog.beginSession('aula', 'l1')!;
      final ex = DiagLog.beginSession('exercicio', 'e1')!;
      DiagLog.log('nota', 'no exercício');
      DiagLog.endSession(ex);
      DiagLog.log('nota', 'de volta à aula');
      expect(store.read(ex.key), contains('no exercício'));
      expect(store.read(aula.key), contains('de volta à aula'));
      expect(store.read(aula.key), isNot(contains('no exercício')));
      expect(DiagLog.collect().map((f) => f.name), contains('${aula.key}.log'));
    },
  );

  test(
    'sessões de uma execução anterior contam e a numeração continua',
    () async {
      final store = MemoryDiagStorage();
      await start(store);
      final first = DiagLog.beginSession('musica', 'x')!;
      DiagLog.log('nota', 'antes de travar');
      DiagLog.reset(); // o app morreu sem encerrar a sessão

      await start(store);
      final s = DiagLog.beginSession('musica', 'y')!;
      expect(s.key, isNot(first.key));
      expect(store.read(first.key), contains('antes de travar'));
      expect(
        DiagLog.collect().map((f) => f.name),
        contains('${first.key}.log'),
      );
    },
  );

  test('o estado registrado vai para o snapshot e o log', () async {
    final store = await start();
    var page = 2;
    final off = DiagLog.setState('partitura', () => {'pagina': page});
    DiagLog.setState('ruim', () => throw StateError('x'));
    expect(DiagLog.snapshot()['partitura'], {'pagina': 2});
    expect(DiagLog.snapshot()['ruim'], contains('erro'));
    page = 3;
    DiagLog.logState('teste');
    expect(store.read('app'), contains('"pagina":3'));
    expect(DiagLog.snapshotJson(), contains('"pagina": 3'));
    off();
    expect(DiagLog.snapshot().containsKey('partitura'), isFalse);
  });

  test('o anexo vai pelo nome e some ao desfazer', () async {
    await start();
    final off = DiagLog.setAttachment('ex.xml', () => '<xml/>');
    DiagLog.setAttachment('ruim', () => throw StateError('x'));
    expect(DiagLog.attachments()['ex.xml'], '<xml/>');
    expect(DiagLog.attachments()['ruim'], contains('erro'));
    off();
    expect(DiagLog.attachments().containsKey('ex.xml'), isFalse);
  });

  test('congelar chama os ganchos, mesmo que um falhe', () async {
    final store = await start();
    var calls = 0;
    DiagLog.addFreezeHook(() => throw StateError('x'));
    final off = DiagLog.addFreezeHook(() => calls++);
    DiagLog.freeze();
    expect(calls, 1);
    expect(store.read('app'), contains('gancho de congelar'));
    off();
    DiagLog.freeze();
    expect(calls, 1);
  });

  test('a memória descarta as linhas mais antigas', () {
    final store = MemoryDiagStorage(maxLines: 8);
    for (var i = 0; i < 20; i++) {
      store.append('k', 'l$i\n');
    }
    final text = store.read('k');
    expect(text, contains('l19'));
    expect(text, isNot(contains('l0\n')));
  });

  group('em arquivos', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('diag_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('grava, lê, lista e remove', () {
      final store = FileDiagStorage(dir.path);
      store.append('s00001', 'a\n');
      store.append('s00001', 'b\n');
      expect(store.read('s00001'), 'a\nb\n');
      expect(store.keys(), ['s00001']);
      store.remove('s00001');
      expect(store.keys(), isEmpty);
    });

    test('passando do limite guarda o trecho anterior', () {
      final store = FileDiagStorage(dir.path, maxBytes: 20);
      for (var i = 0; i < 10; i++) {
        store.append('app', 'linha $i\n');
      }
      final text = store.read('app');
      expect(text, contains('linha 9'));
      // Cada linha tem 8 bytes: a cada 3 o arquivo passa de 20 e vira o
      // trecho anterior (6 a 8), que o seguinte substitui.
      expect(text, contains('linha 6'));
      expect(text, isNot(contains('linha 5')));
      expect(store.keys(), ['app']);
    });
  });
}
