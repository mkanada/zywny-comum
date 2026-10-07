// O que o leitor de ABC do fork do Verovio **não** faz, medido no I02
// (`docs/plano/I02-partituras-das-licoes.md`, notas de execução).

final _voiceLine = RegExp(r'^[ \t]*V:[ \t]*([^\s\]]+)', multiLine: true);
final _voiceInline = RegExp(r'\[V:[ \t]*([^\s\]]+)[^\]]*\]');

/// Problema do [abc] para o zywny, ou `null`. Hoje: várias vozes ou pautas.
/// O leitor avisa "Multi-voice music is not supported" e escreve as vozes
/// **uma depois da outra** (nunca juntas), o que erra o desenho e o tempo.
String? abcProblem(String abc) {
  final voices = {
    for (final m in _voiceLine.allMatches(abc)) m.group(1)!,
    for (final m in _voiceInline.allMatches(abc)) m.group(1)!,
  };
  if (voices.length > 1) {
    return 'o ABC tem várias vozes (${voices.join(', ')}), e o leitor de ABC '
        'do zywny não as toca juntas (elas saem uma depois da outra). Para '
        'duas pautas ou vozes, use um arquivo `.musicxml`.';
  }
  return null;
}
