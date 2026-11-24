// O que o BugReportScope mostra enquanto o relatório está aberto: a tela de
// trás parada, o relatório por cima e a captura da tela de quando ele abriu.
// O State do escopo é o dono deste Cubit, porque `BugReportScope.start` e
// `sendNow` o alcançam de fora da árvore; o `dispose` do State o fecha.

import 'dart:typed_data';

import 'package:zywny_bloc/zywny_bloc.dart';

/// O estado do relatório de bug na tela (o escopo inteiro, não o formulário).
class BugReportFlowState extends Equatable {
  const BugReportFlowState({
    this.parada = false,
    this.formulario = false,
    this.captura,
  });

  /// A tela de trás está parada (animações, som e metrônomo).
  final bool parada;

  /// O relatório está aberto por cima da tela.
  final bool formulario;

  /// A captura da tela como ela estava; `null` se não deu para tirar.
  final Uint8List? captura;

  BugReportFlowState copyWith({
    bool? parada,
    bool? formulario,
    Uint8List? captura,
  }) => BugReportFlowState(
    parada: parada ?? this.parada,
    formulario: formulario ?? this.formulario,
    captura: captura ?? this.captura,
  );

  @override
  List<Object?> get props => [parada, formulario, captura];
}

/// Congela a tela, abre o relatório por cima com a captura e, ao fechar,
/// volta a tela a andar. Não gera nem envia nada: isso é do formulário.
class BugReportFlowCubit extends Cubit<BugReportFlowState> {
  BugReportFlowCubit() : super(const BugReportFlowState());

  /// Para a tela de trás. Chamar de novo sem mudança não emite nada.
  void congelar() => emit(state.copyWith(parada: true));

  /// Abre o relatório por cima, com a captura (ou sem, se não deu para tirar).
  void mostrar(Uint8List? captura) =>
      emit(state.copyWith(formulario: true, captura: captura));

  /// Fecha o relatório e volta a tela a andar (a captura vai embora).
  void fechar() => emit(const BugReportFlowState());
}
