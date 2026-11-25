// O que o app faz fora do quadro e ainda não acabou: o desenho do Verovio, a
// medição da coleção, a carga dos cursos, a leitura do que foi guardado (CT02).
//
// Quem começa um trabalho desses chama `begin(motivo)` e guarda a função que o
// encerra; o app fica "ocupado" até todas as funções serem chamadas. É um
// contador puro (Dart, sem Flutter): o roteiro de capturas lê `isBusy` para
// saber quando o app assentou, e o relatório de bug lê `pendentes` para dizer o
// que estava rodando na hora. Não guarda estado de tela.
import 'dart:async';

/// Um trabalho aberto. A identidade (não o motivo) o distingue dos outros.
class _Trabalho {
  _Trabalho(this.motivo);

  final String motivo;
}

class AppBusy {
  final List<_Trabalho> _abertos = [];
  final List<Completer<void>> _esperas = [];

  /// Há algum trabalho aberto.
  bool get isBusy => _abertos.isNotEmpty;

  /// Os motivos dos trabalhos abertos, do mais antigo para o mais novo.
  List<String> get pendentes => [for (final t in _abertos) t.motivo];

  /// Marca um trabalho em curso com o [motivo] (um texto curto, em português).
  /// Devolve a função que o encerra. Chamá-la de novo não faz nada, e encerrar
  /// um trabalho não mexe nos outros que estão abertos.
  void Function() begin(String motivo) {
    final trabalho = _Trabalho(motivo);
    _abertos.add(trabalho);
    var encerrado = false;
    return () {
      if (encerrado) return;
      encerrado = true;
      _abertos.remove(trabalho);
      if (_abertos.isEmpty) _avisarLivre();
    };
  }

  /// Espera o app ficar livre. Completa na hora se já estiver livre; senão,
  /// quando o último trabalho aberto for encerrado.
  Future<void> whenIdle() {
    if (!isBusy) return Future<void>.value();
    final espera = Completer<void>();
    _esperas.add(espera);
    return espera.future;
  }

  void _avisarLivre() {
    final esperas = List.of(_esperas);
    _esperas.clear();
    for (final espera in esperas) {
      if (!espera.isCompleted) espera.complete();
    }
  }
}
