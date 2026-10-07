import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'piece.dart';

/// Maior `formato` de `.zywny` que este app sabe ler.
const kLibraryFormat = 1;

final _libraryIdPattern = RegExp(r'^[a-z0-9-]{1,40}$');
final _pieceIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,60}$');

/// Erro de leitura de um `.zywny`; [message] já está em português, pronta
/// para a tela.
class LibraryFormatException implements Exception {
  const LibraryFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Como o manifesto manda chamar cada música: "hino"/"hinos" (masculino),
/// "peça"/"peças" (feminino).
@immutable
class LibraryTerm {
  const LibraryTerm({
    required this.singular,
    required this.plural,
    required this.feminine,
  });

  factory LibraryTerm.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const LibraryFormatException(
        'O manifesto da biblioteca não diz como chamar as músicas ("termo").',
      );
    }
    final singular = json['singular'];
    final plural = json['plural'];
    final gender = json['genero'];
    if (singular is! String ||
        singular.trim().isEmpty ||
        plural is! String ||
        plural.trim().isEmpty) {
      throw const LibraryFormatException(
        'O "termo" do manifesto precisa de "singular" e "plural".',
      );
    }
    if (gender != 'm' && gender != 'f') {
      throw const LibraryFormatException(
        'O "termo" do manifesto precisa de "genero": "m" ou "f".',
      );
    }
    return LibraryTerm(
      singular: singular,
      plural: plural,
      feminine: gender == 'f',
    );
  }

  /// "hino"/"hinos" — o termo do hinário (e o padrão sem manifesto).
  static const hymn = LibraryTerm(
    singular: 'hino',
    plural: 'hinos',
    feminine: false,
  );

  final String singular;
  final String plural;
  final bool feminine;

  // Concordância de gênero para os textos fixos da tela (B07): "este hino" /
  // "esta peça", "Nenhum hino encontrado" / "Nenhuma peça encontrada"…
  String get este => feminine ? 'esta' : 'este';
  String get neste => feminine ? 'nesta' : 'neste';
  String get deste => feminine ? 'desta' : 'deste';
  String get nenhum => feminine ? 'nenhuma' : 'nenhum';
  String get nenhumCapitalized => feminine ? 'Nenhuma' : 'Nenhum';
  String get um => feminine ? 'uma' : 'um';
  String get o => feminine ? 'a' : 'o';
  String get os => feminine ? 'as' : 'os';
  String get todos => feminine ? 'todas' : 'todos';
  String get encontrado => feminine ? 'encontrada' : 'encontrado';

  /// "Hino", "Peça": o singular com inicial maiúscula.
  String get singularCapitalized => _capitalized(singular);

  /// "1 hino", "48 peças".
  String count(int n) => '$n ${n == 1 ? singular : plural}';

  static String _capitalized(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  Map<String, dynamic> toJson() => {
    'singular': singular,
    'plural': plural,
    'genero': feminine ? 'f' : 'm',
  };

  @override
  bool operator ==(Object other) =>
      other is LibraryTerm &&
      other.singular == singular &&
      other.plural == plural &&
      other.feminine == feminine;

  @override
  int get hashCode => Object.hash(singular, plural, feminine);
}

/// `manifest.json` de um `.zywny`.
@immutable
class LibraryManifest {
  const LibraryManifest({
    required this.format,
    required this.id,
    required this.name,
    required this.version,
    required this.term,
    required this.numbered,
    this.credits,
    this.language,
  });

  factory LibraryManifest.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const LibraryFormatException(
        'O "manifest.json" da biblioteca não é um objeto JSON.',
      );
    }
    final format = json['formato'];
    if (format is! int) {
      throw const LibraryFormatException(
        'O manifesto da biblioteca não diz o "formato".',
      );
    }
    if (format > kLibraryFormat) {
      throw const LibraryFormatException(
        'Esta biblioteca pede uma versão mais nova do zywny.',
      );
    }
    if (format < 1) {
      throw LibraryFormatException('Formato de biblioteca inválido: $format.');
    }
    final id = json['id'];
    if (id is! String || !_libraryIdPattern.hasMatch(id)) {
      throw LibraryFormatException(
        'O "id" da biblioteca é inválido (use de 1 a 40 letras minúsculas, '
        'números ou hífens): ${id is String ? '"$id"' : 'ausente'}.',
      );
    }
    final name = json['nome'];
    if (name is! String || name.trim().isEmpty) {
      throw const LibraryFormatException(
        'O manifesto da biblioteca não tem "nome".',
      );
    }
    final version = json['versao'];
    if (version is! String || version.trim().isEmpty) {
      throw const LibraryFormatException(
        'O manifesto da biblioteca não tem "versao".',
      );
    }
    final numbered = json['numerada'];
    if (numbered is! bool) {
      throw const LibraryFormatException(
        'O manifesto da biblioteca precisa de "numerada": true ou false.',
      );
    }
    return LibraryManifest(
      format: format,
      id: id,
      name: name,
      version: version,
      term: LibraryTerm.fromJson(json['termo']),
      numbered: numbered,
      credits: json['creditos'] as String?,
      language: json['idioma'] as String?,
    );
  }

  final int format;

  /// Chave de tudo o que o app guarda da biblioteca; não muda entre versões.
  final String id;
  final String name;

  /// Texto livre; só se mostra, o app não compara.
  final String version;
  final LibraryTerm term;

  /// Se toda peça tem número (`n`) e a ordem "Número" existe.
  final bool numbered;
  final String? credits;
  final String? language;
}

/// Um `.zywny` aberto: manifesto, índice e as partituras ainda compactadas.
/// Só lê bytes — nada de disco, preferências ou widgets.
class LibraryPackage {
  LibraryPackage._(this.manifest, this.pieces, this._scores);

  /// Valida o pacote inteiro; qualquer problema vira uma
  /// [LibraryFormatException] e nada é devolvido pela metade.
  factory LibraryPackage.parse(Uint8List bytes) {
    final Archive archive;
    try {
      // O decodificador do `archive` aceita lixo e devolve um zip vazio;
      // a assinatura "PK" é o que separa um zip de um arquivo qualquer.
      if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
        throw const FormatException('sem assinatura de zip');
      }
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const LibraryFormatException(
        'Este arquivo não é uma biblioteca do zywny (não é um .zip válido).',
      );
    }
    final files = <String, ArchiveFile>{
      for (final f in archive)
        if (f.isFile) f.name: f,
    };
    final manifest = LibraryManifest.fromJson(
      _json(files, 'manifest.json', 'o manifesto'),
    );
    final indexJson = _json(files, 'indice.json', 'o índice');
    if (indexJson is! List) {
      throw const LibraryFormatException(
        'O "indice.json" da biblioteca deveria ser uma lista de músicas.',
      );
    }

    final pieces = <Piece>[];
    final scores = <String, ArchiveFile>{};
    final seenNumbers = <int>{};
    for (var i = 0; i < indexJson.length; i++) {
      final entry = indexJson[i];
      final where = 'Música ${i + 1} do índice';
      if (entry is! Map<String, dynamic>) {
        throw LibraryFormatException('$where não é um objeto JSON.');
      }
      final id = entry['id'];
      if (id is! String || !_pieceIdPattern.hasMatch(id)) {
        throw LibraryFormatException(
          '$where tem "id" inválido: ${id is String ? '"$id"' : 'ausente'}.',
        );
      }
      if (scores.containsKey(id)) {
        throw LibraryFormatException('O id "$id" aparece mais de uma vez.');
      }
      final file = files['partituras/$id.musicxml.gz'];
      if (file == null) {
        throw LibraryFormatException(
          'A música "$id" está no índice mas não tem partitura em '
          '"partituras/$id.musicxml.gz".',
        );
      }
      scores[id] = file;

      Object? n;
      if (manifest.numbered) {
        n = entry['n'];
        if (n is! int) {
          throw LibraryFormatException(
            'A biblioteca é numerada, mas a música "$id" não tem número ("n").',
          );
        }
        if (!seenNumbers.add(n)) {
          throw LibraryFormatException(
            'O número $n aparece em mais de uma música.',
          );
        }
      }
      for (final field in const ['t', 'c', 'k', 'ck', 'q']) {
        if (entry[field] is! String) {
          throw LibraryFormatException(
            'A música "$id" não tem o campo obrigatório "$field".',
          );
        }
      }
      // A troca de `Piece` por `Piece` (número opcional) é do B04; até lá, uma
      // biblioteca sem número usa a posição no índice como número provisório.
      pieces.add(Piece.fromJson({...entry, 'n': n ?? i + 1}));
    }
    return LibraryPackage._(manifest, List.unmodifiable(pieces), scores);
  }

  static Object? _json(
    Map<String, ArchiveFile> files,
    String name,
    String what,
  ) {
    final file = files[name];
    if (file == null) {
      throw LibraryFormatException(
        'Falta o arquivo "$name" ($what) dentro da biblioteca.',
      );
    }
    try {
      return jsonDecode(utf8.decode(file.content as List<int>));
    } catch (_) {
      throw LibraryFormatException('Não consegui ler "$name": JSON inválido.');
    }
  }

  final LibraryManifest manifest;
  final List<Piece> pieces;
  final Map<String, ArchiveFile> _scores;

  /// Descompacta a partitura de [id] e devolve o `.musicxml`. O `gzip` é do
  /// `archive` (o de `dart:io` não existe na Web).
  Future<Uint8List> loadScore(String id) async {
    final file = _scores[id];
    if (file == null) {
      throw ArgumentError.value(id, 'id', 'não existe nesta biblioteca');
    }
    return Uint8List.fromList(
      GZipDecoder().decodeBytes(file.content as List<int>),
    );
  }
}
