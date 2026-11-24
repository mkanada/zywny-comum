import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/diag/bug_report_delivery.dart';
import 'package:zywny_comum/diag/bug_report_form_cubit.dart';
import 'package:zywny_comum/diag/bug_report_sender.dart';

const _entrega = BugReportDelivery(savedAt: 'Download/zywny-bug.zip');
const _codigo = BugReportReceipt('ABC123');

void main() {
  group('BugReportFormState', () {
    test('começa sem ocupado, sem erro e sem resultado', () {
      const estado = BugReportFormState();

      expect(estado.ocupado, isFalse);
      expect(estado.erro, isNull);
      expect(estado.gerado, isNull);
      expect(estado.enviado, isNull);
    });

    test('copyWith com limparErro tira o erro', () {
      const comErro = BugReportFormState(erro: 'Muitos.');

      expect(comErro.copyWith(limparErro: true).erro, isNull);
      expect(comErro.copyWith().erro, 'Muitos.');
    });
  });

  group('BugReportFormCubit', () {
    test('podeEnviar só com o envio do aparelho', () {
      final sem = BugReportFormCubit(onSubmit: (_, _) async => _entrega);
      final com = BugReportFormCubit(
        onSubmit: (_, _) async => _entrega,
        onSend: (_, _) async => _codigo,
      );
      addTearDown(sem.close);
      addTearDown(com.close);

      expect(sem.podeEnviar, isFalse);
      expect(com.podeEnviar, isTrue);
    });

    blocTest<BugReportFormCubit, BugReportFormState>(
      'gerar mostra ocupado e depois o arquivo',
      build: () => BugReportFormCubit(onSubmit: (_, _) async => _entrega),
      act: (cubit) => cubit.gerar('tocando', 'travou'),
      expect: () => [
        const BugReportFormState(ocupado: true),
        const BugReportFormState(gerado: _entrega),
      ],
    );

    blocTest<BugReportFormCubit, BugReportFormState>(
      'gerar com falha mostra o erro e sai do ocupado',
      build: () => BugReportFormCubit(
        onSubmit: (_, _) => Future.error(StateError('disco cheio')),
      ),
      act: (cubit) => cubit.gerar('tocando', 'travou'),
      expect: () => [
        const BugReportFormState(ocupado: true),
        const BugReportFormState(
          erro: 'Não consegui gerar o arquivo: Bad state: disco cheio',
        ),
      ],
    );

    blocTest<BugReportFormCubit, BugReportFormState>(
      'enviar mostra o código que a equipe deu',
      build: () => BugReportFormCubit(
        onSubmit: (_, _) async => _entrega,
        onSend: (_, _) async => _codigo,
      ),
      act: (cubit) => cubit.enviar('tocando', 'travou'),
      expect: () => [
        const BugReportFormState(ocupado: true),
        const BugReportFormState(enviado: _codigo),
      ],
    );

    blocTest<BugReportFormCubit, BugReportFormState>(
      'a recusa da equipe mostra o motivo dela',
      build: () => BugReportFormCubit(
        onSubmit: (_, _) async => _entrega,
        onSend: (_, _) async =>
            throw const BugReportSendException('Muitos relatórios hoje.'),
      ),
      act: (cubit) => cubit.enviar('tocando', 'travou'),
      expect: () => [
        const BugReportFormState(ocupado: true),
        const BugReportFormState(erro: 'Muitos relatórios hoje.'),
      ],
    );

    blocTest<BugReportFormCubit, BugReportFormState>(
      'falha de rede no envio dá a mensagem genérica',
      build: () => BugReportFormCubit(
        onSubmit: (_, _) async => _entrega,
        onSend: (_, _) => Future.error(StateError('sem rede')),
      ),
      act: (cubit) => cubit.enviar('tocando', 'travou'),
      expect: () => [
        const BugReportFormState(ocupado: true),
        const BugReportFormState(
          erro:
              'Não consegui enviar agora (sem rede?). Tente de novo ou '
              'gere o arquivo.',
        ),
      ],
    );

    test(
      'se a tela sair durante o envio, a resposta não emite nem lança',
      () async {
        final resposta = Completer<BugReportReceipt>();
        final cubit = BugReportFormCubit(
          onSubmit: (_, _) async => _entrega,
          onSend: (_, _) => resposta.future,
        );

        final envio = cubit.enviar('tocando', 'travou');
        await cubit.close();
        resposta.complete(_codigo);

        await expectLater(envio, completes);
        expect(cubit.isClosed, isTrue);
        expect(cubit.state, const BugReportFormState(ocupado: true));
      },
    );
  });
}
