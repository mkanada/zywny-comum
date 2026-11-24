import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zywny_comum/diag/diag_screens.dart';
import 'package:zywny_diag/diag_log.dart';

/// Quantas vezes a tela de dentro foi montada.
int _montagens = 0;

class _Dentro extends StatefulWidget {
  const _Dentro();

  @override
  State<_Dentro> createState() => _DentroState();
}

class _DentroState extends State<_Dentro> {
  @override
  void initState() {
    super.initState();
    _montagens++;
  }

  @override
  Widget build(BuildContext context) => const Text('dentro');
}

void main() {
  late MemoryDiagStorage store;

  setUp(() async {
    _montagens = 0;
    store = MemoryDiagStorage();
    await DiagLog.init(storage: store, installHandlers: false);
  });
  tearDown(DiagLog.reset);

  // A sessão cujo texto diz `nome="<nome>"`.
  String sessao(String nome) => store
      .keys()
      .where((k) => k != 'app')
      .map((k) => store.read(k))
      .firstWhere((t) => t.contains('nome="$nome"'));

  Widget tela(String name) => Directionality(
    textDirection: TextDirection.ltr,
    child: DiagSessionScope(
      kind: 'exercicio',
      name: name,
      child: const _Dentro(),
    ),
  );

  testWidgets('trocar o nome troca a sessão e não remonta a tela de dentro', (
    tester,
  ) async {
    await tester.pumpWidget(tela('1'));
    expect(_montagens, 1);
    expect(DiagScreens.screens, ['exercicio 1']);

    await tester.pumpWidget(tela('2'));

    expect(_montagens, 1, reason: 'o filho continua montado');
    expect(DiagScreens.screens, ['exercicio 2']);
    expect(sessao('1'), contains('[sessao] fim: exercicio 1'));
    expect(sessao('2'), contains('tela aberta: exercicio 2'));
  });

  testWidgets('sair da tela fecha a tela antes de encerrar a sessão', (
    tester,
  ) async {
    await tester.pumpWidget(tela('3'));

    await tester.pumpWidget(const SizedBox());

    expect(DiagScreens.screens, isEmpty);
    final texto = sessao('3');
    expect(texto, contains('tela fechada: exercicio 3'));
    expect(
      texto.indexOf('tela fechada: exercicio 3'),
      lessThan(texto.indexOf('[sessao] fim: exercicio 3')),
    );
  });
}
