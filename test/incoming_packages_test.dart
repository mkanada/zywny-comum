// B11 — o `.zywny` que o sistema entrega ao app: a fila, os argumentos de
// `main` e o canal nativo (Android; Linux com o app já aberto).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny/incoming/incoming_packages.dart';

IncomingPackage _package(String name) =>
    IncomingPackage(name: name, read: () async => Uint8List(0));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('caminhos', () {
    test('só o que termina em .zywny, em qualquer caixa', () {
      expect(isPackagePath('/tmp/hinos.zywny'), isTrue);
      expect(isPackagePath(r'C:\Users\eu\Hinos.ZYWNY'), isTrue);
      expect(isPackagePath('/tmp/hinos.zip'), isFalse);
      expect(isPackagePath('/tmp/hinos.zywny.bak'), isFalse);
    });

    test('opções e outros argumentos passam batido', () {
      expect(
        packagePathsIn([
          '--debug',
          '/tmp/hinos.zywny',
          '--curso',
          '/tmp/curso',
          'classicos.zywny',
          '--x.zywny',
        ]),
        ['/tmp/hinos.zywny', 'classicos.zywny'],
      );
      expect(packagePathsIn(const []), isEmpty);
    });

    test('um file:// vira o caminho, com os espaços e acentos de volta', () {
      expect(
        packagePathsIn(['file:///home/eu/M%C3%BAsica/meus%20hinos.zywny']),
        ['/home/eu/Música/meus hinos.zywny'],
      );
    });

    test('o nome é o último trecho, com / ou \\', () {
      expect(baseName('/home/eu/Downloads/hinos.zywny'), 'hinos.zywny');
      expect(baseName(r'C:\Users\eu\hinos.zywny'), 'hinos.zywny');
      expect(baseName('hinos.zywny'), 'hinos.zywny');
    });
  });

  group('a fila', () {
    test('o que chega antes de alguém se ligar espera, na ordem', () {
      final queue = IncomingPackages()
        ..add(_package('a'))
        ..add(_package('b'));
      expect(queue.hasWaiting, isTrue);

      final got = <String>[];
      queue.attach((p) => got.add(p.name));
      expect(got, ['a', 'b']);
      expect(queue.hasWaiting, isFalse);

      queue.add(_package('c'));
      expect(got, ['a', 'b', 'c']);
    });

    test('depois de desligar, o que vier volta a esperar', () {
      final queue = IncomingPackages();
      final got = <String>[];
      void listener(IncomingPackage p) => got.add(p.name);
      queue.attach(listener);
      queue.detach(listener);
      queue.add(_package('a'));
      expect(got, isEmpty);
      expect(queue.hasWaiting, isTrue);

      final again = <String>[];
      queue.attach((p) => again.add(p.name));
      expect(again, ['a']);
    });

    test('desligar um ouvinte antigo não derruba o novo', () {
      final queue = IncomingPackages();
      final got = <String>[];
      void old(IncomingPackage p) {}
      queue.attach(old);
      queue.attach((p) => got.add(p.name));
      queue.detach(old);
      queue.add(_package('a'));
      expect(got, ['a']);
    });
  });

  group('o canal nativo', () {
    const channel = MethodChannel('teste/incoming');
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('zywny_incoming_');
      addTearDown(() => tmp.deleteSync(recursive: true));
    });

    void answerInitial(Object? Function() reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'initial') return reply();
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    }

    /// O nativo empurra um arquivo com o app já aberto.
    Future<void> push(Map<String, Object?> payload) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(MethodCall('file', payload)),
            (_) {},
          );
    }

    test('argumentos de main viram pacotes, com o nome do arquivo', () async {
      final file = File('${tmp.path}/hinos.zywny')
        ..writeAsBytesSync(utf8.encode('conteúdo'));
      final queue = IncomingPackages();
      await listenForIncomingPackages(
        queue,
        args: ['--debug', file.path],
        channel: channel,
      );
      final got = <IncomingPackage>[];
      queue.attach(got.add);
      expect(got.map((p) => p.name), ['hinos.zywny']);
      expect(utf8.decode(await got.single.read()), 'conteúdo');
      expect(file.existsSync(), isTrue, reason: 'o arquivo do usuário fica');
    });

    test('o que o nativo guardou antes de o Dart perguntar vem em '
        '"initial"', () async {
      final copy = File('${tmp.path}/copia.zywny')
        ..writeAsBytesSync(const [1, 2, 3]);
      answerInitial(
        () => [
          {'name': 'hinos.zywny', 'path': copy.path, 'temporary': true},
        ],
      );
      final queue = IncomingPackages();
      await listenForIncomingPackages(queue, channel: channel);
      final got = <IncomingPackage>[];
      queue.attach(got.add);

      expect(got.single.name, 'hinos.zywny');
      expect(await got.single.read(), [1, 2, 3]);
      // A cópia do cache é apagada depois de lida.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(copy.existsSync(), isFalse);
    });

    test('um arquivo empurrado com o app aberto vai a quem está ligado, e '
        'o do usuário não é apagado', () async {
      answerInitial(() => const <Object?>[]);
      final queue = IncomingPackages();
      final got = <IncomingPackage>[];
      queue.attach(got.add);
      await listenForIncomingPackages(queue, channel: channel);

      final mine = File('${tmp.path}/classicos.zywny')
        ..writeAsBytesSync(const [9]);
      await push({'name': 'classicos.zywny', 'path': mine.path});

      expect(got.single.name, 'classicos.zywny');
      expect(await got.single.read(), [9]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mine.existsSync(), isTrue);
    });

    test(
      'um erro do nativo vira pacote que falha ao ler, com o motivo',
      () async {
        answerInitial(
          () => [
            {'name': 'hinos.zywny', 'error': 'Permission denied'},
          ],
        );
        final queue = IncomingPackages();
        await listenForIncomingPackages(queue, channel: channel);
        final got = <IncomingPackage>[];
        queue.attach(got.add);
        expect(got.single.name, 'hinos.zywny');
        await expectLater(got.single.read(), throwsA('Permission denied'));
      },
    );

    test(
      'sem o lado nativo (testes, Web, Windows) não acontece nada',
      () async {
        // Nenhum handler registrado: o canal responde "não implementado".
        final queue = IncomingPackages();
        await listenForIncomingPackages(queue, channel: channel);
        expect(queue.hasWaiting, isFalse);
      },
    );

    test('carga que não é o combinado é ignorada', () async {
      answerInitial(() => ['isto não é um mapa', <String, Object?>{}]);
      final queue = IncomingPackages();
      await listenForIncomingPackages(queue, channel: channel);
      expect(queue.hasWaiting, isFalse);
    });
  });
}
