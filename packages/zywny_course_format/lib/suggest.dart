/// "Você quis dizer": a palavra de [candidates] mais parecida com [word]
/// (distância de edição ≤ 2, sem diferenciar maiúsculas), ou `null`.
String? suggestSimilar(String word, Iterable<String> candidates) {
  final lower = word.toLowerCase();
  String? best;
  var bestDistance = 3;
  for (final candidate in candidates) {
    final distance = _editDistance(lower, candidate.toLowerCase());
    if (distance < bestDistance) {
      bestDistance = distance;
      best = candidate;
    }
  }
  return best;
}

/// Palavras em português que um autor tende a escrever no lugar da chave ou
/// da marca em inglês. Só valem se a chave existir onde o erro aconteceu.
const kPortugueseAliases = <String, String>{
  'titulo': 'title',
  'tipo': 'type',
  'notas': 'notes',
  'clave': 'clef',
  'tom': 'key',
  'armadura': 'key',
  'compasso': 'time',
  'compassos': 'measures',
  'legenda': 'caption',
  'arquivo': 'file',
  'andamento': 'bpm',
  'rodadas': 'rounds',
  'precisao': 'accuracy',
  'precisão': 'accuracy',
  'autor': 'author',
  'versao': 'version',
  'versão': 'version',
  'licoes': 'lessons',
  'lições': 'lessons',
  'requer': 'requires',
  'mao': 'hand',
  'mão': 'hand',
  'modo': 'mode',
  'figuras': 'figures',
  'opcoes': 'options',
  'opções': 'options',
  'resposta': 'answer',
  'pergunta': 'question',
  'imagem': 'image',
  'ritmo': 'rhythm',
  'escolha': 'choice',
  'exercicio': 'exercise',
  'exercício': 'exercise',
  'partitura': 'score',
  'teclado': 'keyboard',
  'video': 'video',
  'vídeo': 'video',
  'áudio': 'audio',
};

/// A sugestão para [word]: um apelido em português ou a palavra parecida.
String? suggestFor(String word, Iterable<String> candidates) {
  final alias = kPortugueseAliases[word.toLowerCase()];
  if (alias != null && candidates.contains(alias)) return alias;
  return suggestSimilar(word, candidates);
}

int _editDistance(String a, String b) {
  if (a == b) return 0;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}
