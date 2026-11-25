import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_diag/app_busy.dart';

void main() {
  group('AppBusy', () {
    test('começa livre, sem nada pendente', () {
      final busy = AppBusy();
      expect(busy.isBusy, isFalse);
      expect(busy.pendentes, isEmpty);
    });

    test('um trabalho aberto deixa o app ocupado até ser encerrado', () {
      final busy = AppBusy();
      final encerrar = busy.begin('desenho da partitura');
      expect(busy.isBusy, isTrue);
      expect(busy.pendentes, ['desenho da partitura']);
      encerrar();
      expect(busy.isBusy, isFalse);
      expect(busy.pendentes, isEmpty);
    });

    test('vários trabalhos: livre só quando o último encerra', () {
      final busy = AppBusy();
      final a = busy.begin('carga dos cursos');
      final b = busy.begin('medição da coleção');
      expect(busy.pendentes, ['carga dos cursos', 'medição da coleção']);
      a();
      expect(busy.isBusy, isTrue);
      expect(busy.pendentes, ['medição da coleção']);
      b();
      expect(busy.isBusy, isFalse);
    });

    test('encerrar duas vezes não tira outro trabalho aberto', () {
      final busy = AppBusy();
      final a = busy.begin('a');
      busy.begin('b');
      a();
      a();
      expect(busy.pendentes, ['b']);
    });

    test('dois trabalhos com o mesmo motivo são contados à parte', () {
      final busy = AppBusy();
      final primeiro = busy.begin('render');
      final segundo = busy.begin('render');
      primeiro();
      expect(busy.isBusy, isTrue);
      expect(busy.pendentes, ['render']);
      segundo();
      expect(busy.isBusy, isFalse);
    });

    test('whenIdle completa na hora se o app já está livre', () async {
      final busy = AppBusy();
      var feito = false;
      await busy.whenIdle().then((_) => feito = true);
      expect(feito, isTrue);
    });

    test('whenIdle espera o último trabalho encerrar', () async {
      final busy = AppBusy();
      final encerrar = busy.begin('leitura do que foi guardado');
      var feito = false;
      final espera = busy.whenIdle().then((_) => feito = true);
      await Future<void>.delayed(Duration.zero);
      expect(feito, isFalse);
      encerrar();
      await espera;
      expect(feito, isTrue);
    });

    test('whenIdle só completa quando tudo acabou', () async {
      final busy = AppBusy();
      final a = busy.begin('a');
      final b = busy.begin('b');
      var feito = false;
      final espera = busy.whenIdle().then((_) => feito = true);
      a();
      await Future<void>.delayed(Duration.zero);
      expect(feito, isFalse);
      b();
      await espera;
      expect(feito, isTrue);
    });

    test(
      'um trabalho com Future: encerrar no whenComplete libera o app',
      () async {
        final busy = AppBusy();
        final conta = Completer<int>();
        final feito = conta.future.whenComplete(busy.begin('conta'));
        expect(busy.isBusy, isTrue);
        conta.complete(42);
        await feito;
        expect(busy.isBusy, isFalse);
      },
    );
  });
}
