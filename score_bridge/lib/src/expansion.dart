// Ids expandidos do timemap (`-rend<N>`) → nó da cena (E02a).
//
// Uma peça com repetição tem, no timemap, ids que não existem em
// `scene.json`: a cena é sempre a do documento notado (sem repetição), e o
// timemap vem de uma cópia expandida internamente pelo Verovio, em que cada
// trecho repetido vira um clone com o id `<id notado>-rend<N>` (`N` = a
// N-ésima execução; a 1ª usa o id notado sem sufixo). Ver
// docs/formato/especificacao-v1.md §2.4 (D-EXPMAP, decisão do usuário em
// 2026-09-21: regra do sufixo, sem arquivo `expansion.json` à parte).
library;

final RegExp _rendSuffix = RegExp(r'^(.*)-rend([0-9]+)$');

/// Resolve ids do timemap ao `xml:id` da cena e à passagem que representam,
/// com memo (o timemap tem até ~2 500 ids distintos por peça).
///
/// **Nunca** tira o sufixo de um id que já existe na cena: se o host desenhar
/// a partitura já expandida (`--expand-always`), os clones `-rend2` estão na
/// cena como nós próprios, e são eles mesmos.
class IdExpansion {
  IdExpansion(this._sceneIds);

  final Set<String> _sceneIds;
  final Map<String, String?> _sceneIdCache = {};
  final Map<String, int> _passCache = {};

  /// Id do nó da cena que [id] representa (ele mesmo, ou a base de um
  /// `-rend<N>`), ou `null` se [id] não pertence à cena.
  String? sceneIdOf(String id) => _sceneIdCache.putIfAbsent(id, () {
    if (_sceneIds.contains(id)) {
      return id;
    }
    final match = _rendSuffix.firstMatch(id);
    if (match != null && _sceneIds.contains(match.group(1))) {
      return match.group(1);
    }
    return null;
  });

  /// A execução que [id] representa: N de `-rend<N>`; 1 para o id da cena (e
  /// para um id desconhecido — chame [sceneIdOf] primeiro para saber se ele
  /// pertence à cena).
  int passOf(String id) => _passCache.putIfAbsent(id, () {
    if (_sceneIds.contains(id)) {
      return 1;
    }
    final match = _rendSuffix.firstMatch(id);
    if (match != null && _sceneIds.contains(match.group(1))) {
      return int.parse(match.group(2)!);
    }
    return 1;
  });
}
