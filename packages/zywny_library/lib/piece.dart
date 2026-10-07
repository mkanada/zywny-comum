import 'package:flutter/foundation.dart';

import 'library_package.dart';

/// Id da biblioteca de hinos: a do pacote `hinos.zywny` e a do índice
/// embutido de antes da fase B.
const kHymnsLibraryId = 'hinos';

/// Uma música de uma biblioteca — uma linha do `indice.json` do pacote
/// `.zywny` (docs/plano/B00; os hinos vêm de `tool/build_hymn_assets.py`).
@immutable
class Piece {
  Piece({
    this.libraryId = kHymnsLibraryId,
    String? id,
    this.number,
    required this.title,
    required this.composer,
    this.lyricist,
    this.originalTitle,
    this.level,
    this.difficulty,
    this.fifths,
    required this.titleKey,
    required this.composerKey,
    required this.searchKey,
  }) : assert(id != null || number != null, 'sem id nem número'),
       id = id ?? number!.toString().padLeft(3, '0');

  /// [libraryId] vem do manifesto do pacote. O índice embutido de hoje não
  /// tem `id`: vale o número com três dígitos.
  factory Piece.fromJson(
    Map<String, dynamic> json, {
    String libraryId = kHymnsLibraryId,
  }) => Piece(
    libraryId: libraryId,
    id: json['id'] as String?,
    number: json['n'] as int?,
    title: json['t'] as String,
    composer: json['c'] as String,
    lyricist: json['l'] as String?,
    originalTitle: json['o'] as String?,
    level: json['nv'] as int?,
    difficulty: (json['d'] as num?)?.toDouble(),
    fifths: json['a'] as int?,
    titleKey: json['k'] as String,
    composerKey: json['ck'] as String,
    searchKey: json['q'] as String,
  );

  /// A biblioteca a que a música pertence: com o [id], a chave de tudo o que
  /// o app guarda dela (progresso, ajustes, trilha).
  final String libraryId;

  /// Nome do arquivo em `partituras/`; nos hinos, o número com três dígitos.
  final String id;

  /// Só nas bibliotecas numeradas (o hinário); `null` nas demais.
  final int? number;
  final String title;
  final String composer;

  /// Autor da letra, só quando não é o próprio compositor.
  final String? lyricist;

  /// Título original — nos clássicos, o número de catálogo ("Op. 100 nº 2").
  final String? originalTitle;

  /// Nível de dificuldade, de 1 (mais fácil) a 5, e a nota contínua de onde
  /// ele sai (`_dificuldade.csv` do Hymn_Grabber) — a nota é a chave de
  /// ordem, o nível é o que se mostra. `null` numa música não classificada.
  final int? level;
  final double? difficulty;

  /// Armadura do início: sustenidos (positivo) ou bemóis (negativo);
  /// `null` num índice antigo, sem o campo.
  final int? fifths;

  /// Quantos acidentes a armadura tem (sem sinal), para ordenar.
  int? get accidentals => fifths?.abs();

  /// Chaves sem acento nem pontuação, prontas do índice: ordem por título,
  /// ordem por compositor e o texto onde a busca procura (número, títulos e
  /// autores).
  final String titleKey;
  final String composerKey;
  final String searchKey;
}

/// As músicas da biblioteca em uso. Pode ser vazio por não haver biblioteca
/// instalada ([PieceCatalog.none], que a tela trata como "instale uma") — um
/// erro de leitura, ao contrário, sai como exceção do carregamento.
class PieceCatalog {
  const PieceCatalog(
    this.pieces, {
    this.libraryId = kHymnsLibraryId,
    this.libraryName = 'Hinário',
    this.term = LibraryTerm.hymn,
    this.numbered = true,
    Future<Uint8List> Function(Piece piece)? scoreLoader,
    // ignore: prefer_initializing_formals
  }) : _scoreLoader = scoreLoader;

  /// Nenhuma biblioteca instalada.
  const PieceCatalog.none()
    : pieces = const [],
      libraryId = null,
      libraryName = '',
      term = LibraryTerm.hymn,
      numbered = false,
      _scoreLoader = null;

  /// O catálogo de um pacote aberto.
  factory PieceCatalog.fromPackage(LibraryPackage package) {
    final m = package.manifest;
    return PieceCatalog(
      package.pieces,
      libraryId: m.id,
      libraryName: m.name,
      term: m.term,
      numbered: m.numbered,
      scoreLoader: (piece) => package.loadScore(piece.id),
    );
  }

  final List<Piece> pieces;

  /// `null` sem biblioteca instalada.
  final String? libraryId;
  final String libraryName;

  /// Como o manifesto manda chamar cada música, e se elas são numeradas.
  final LibraryTerm term;
  final bool numbered;
  final Future<Uint8List> Function(Piece piece)? _scoreLoader;

  bool get hasLibrary => libraryId != null;

  /// Descompacta a música e devolve o `.musicxml` em memória: a renderização
  /// (`ScoreRenderer`) recebe bytes, porque na Web não há disco — o lado
  /// nativo é que grava o arquivo temporário que o Verovio exige.
  Future<Uint8List> loadScore(Piece piece) {
    final load = _scoreLoader;
    if (load == null) {
      throw StateError('catálogo sem biblioteca: não há partitura a abrir');
    }
    return load(piece);
  }
}

/// Minúsculas sem acento nem pontuação — o mesmo `fold` do
/// `tool/build_hymn_assets.py`, para o que o usuário digita na busca casar
/// com [Piece.searchKey].
String foldForSearch(String text) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final out = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();
}

/// Acidentes da armadura em português: "2 sustenidos", "1 bemol", "sem
/// acidentes". `fifths` como no MusicXML (positivo = sustenidos).
String keySignatureLabel(int fifths) {
  final n = fifths.abs();
  if (n == 0) return 'sem acidentes';
  final what = fifths > 0
      ? (n == 1 ? 'sustenido' : 'sustenidos')
      : (n == 1 ? 'bemol' : 'bemóis');
  return '$n $what';
}
