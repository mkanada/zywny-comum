import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import 'legacy_migration.dart';
import 'library_blob_store.dart';
import 'library_envelope.dart';
import 'library_package.dart';
import 'piece.dart' show kHymnsLibraryId;

/// O que o app lembra de cada biblioteca instalada, para as configurações
/// listarem sem abrir cada pacote.
@immutable
class InstalledLibrary {
  const InstalledLibrary({
    required this.id,
    required this.name,
    required this.version,
    required this.term,
    required this.numbered,
    required this.pieceCount,
    this.credits,
  });

  factory InstalledLibrary.fromPackage(LibraryPackage package) {
    final m = package.manifest;
    return InstalledLibrary(
      id: m.id,
      name: m.name,
      version: m.version,
      term: m.term,
      numbered: m.numbered,
      pieceCount: package.pieces.length,
      credits: m.credits,
    );
  }

  factory InstalledLibrary.fromJson(Map<String, dynamic> json) =>
      InstalledLibrary(
        id: json['id'] as String,
        name: json['nome'] as String,
        version: json['versao'] as String,
        term: LibraryTerm.fromJson(json['termo']),
        numbered: json['numerada'] as bool,
        pieceCount: json['pecas'] as int,
        credits: json['creditos'] as String?,
      );

  final String id;
  final String name;
  final String version;
  final LibraryTerm term;
  final bool numbered;
  final int pieceCount;

  /// Texto livre do manifesto: origem, licença, quem montou.
  final String? credits;

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': name,
    'versao': version,
    'termo': term.toJson(),
    'numerada': numbered,
    'pecas': pieceCount,
    'creditos': ?credits,
  };
}

/// As bibliotecas instaladas e qual está em uso (D-BIB-UMA). Imutável: cada
/// mudança é outro estado.
class LibraryState extends Equatable {
  const LibraryState({this.installed = const [], this.activeId});

  /// Em ordem de instalação.
  final List<InstalledLibrary> installed;

  /// O `id` da biblioteca em uso, ou `null` se não há nenhuma.
  final String? activeId;

  InstalledLibrary? get active => this[activeId];

  InstalledLibrary? operator [](String? id) {
    for (final lib in installed) {
      if (lib.id == id) return lib;
    }
    return null;
  }

  /// Troca só o que vier (`null` mantém). Para tirar a em uso, use o
  /// construtor.
  LibraryState copyWith({
    List<InstalledLibrary>? installed,
    String? activeId,
  }) => LibraryState(
    installed: installed == null
        ? this.installed
        : List.unmodifiable(installed),
    activeId: activeId ?? this.activeId,
  );

  @override
  List<Object?> get props => [installed, activeId];
}

/// As bibliotecas instaladas e qual está em uso. Os bytes dos pacotes ficam
/// num [LibraryBlobStore] (arquivo, IndexedDB ou memória); a lista e o `id` em
/// uso, em `shared_preferences` (`library_installed`, `library_active`). Cada
/// mudança é gravada antes de ser emitida: o estado não anda na frente do
/// disco.
class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit({
    LibraryBlobStore? blobs,
    SharedPreferencesAsync? prefs,
    Uint8List? publicKey,
  }) : _blobs = blobs ?? createLibraryBlobStore(),
       _prefs = prefs ?? SharedPreferencesAsync(),
       _publicKey = publicKey ?? libraryKeyFromEnvironment(),
       super(const LibraryState());

  static const installedKey = 'library_installed';
  static const activeKey = 'library_active';

  final LibraryBlobStore _blobs;
  final SharedPreferencesAsync _prefs;
  final Uint8List? _publicKey;

  /// A chave pública que abre os pacotes (`null` sem chave no build): o
  /// despacho do instalador usa esta ou a dos cursos (a mesma pessoa assina
  /// os dois, D-LIC-CONFIANCA).
  Uint8List? get publicKey => _publicKey;

  /// Lê a lista e a em uso das preferências. O que está na lista mas não tem
  /// pacote (arquivo apagado, dados do site limpos) sai dela.
  Future<void> load() async {
    final installed = <InstalledLibrary>[];
    final text = await _prefs.getString(installedKey);
    if (text != null) {
      try {
        for (final e in jsonDecode(text) as List<dynamic>) {
          final lib = InstalledLibrary.fromJson(e as Map<String, dynamic>);
          if (await _blobs.contains(lib.id)) installed.add(lib);
        }
      } on Object {
        // Lista estragada: recomeça vazia em vez de travar o app.
        installed.clear();
      }
    }
    final saved = await _prefs.getString(activeKey);
    final activeId = installed.any((e) => e.id == saved)
        ? saved
        : (installed.isEmpty ? null : installed.first.id);
    if (isClosed) return;
    emit(
      LibraryState(installed: List.unmodifiable(installed), activeId: activeId),
    );
  }

  /// Abre o pacote de [id] (assinatura, cifra e conteúdo) ou `null` se não
  /// está instalado.
  Future<LibraryPackage?> open(String id) async {
    final bytes = await _blobs.get(id);
    if (bytes == null) return null;
    return openLibraryPackage(bytes, _requireKey());
  }

  /// Os bytes do pacote de [id], como foram instalados (o envelope).
  Future<Uint8List?> read(String id) => _blobs.get(id);

  /// Abre [bytes] (assinatura, cifra e conteúdo) sem gravar nada: a tela usa
  /// isto para conferir o pacote e perguntar antes de substituir uma
  /// biblioteca instalada.
  Future<LibraryPackage> inspect(Uint8List bytes) =>
      openLibraryPackage(bytes, _requireKey());

  /// Valida [bytes] (assinatura, cifra e conteúdo) **antes de gravar**; se
  /// falhar, nada muda. Um `id` já instalado é substituído — quem pergunta
  /// ao usuário antes é a tela (D-BIB-ATUALIZAR). A biblioteca instalada
  /// vira a em uso (D-BIB-NOVA) a menos que [activate] seja `false`. A primeira vez que a biblioteca de
  /// hinos entra, o progresso de antes da fase B migra para ela
  /// ([migrateLegacyHymnKeys]).
  Future<InstalledLibrary> install(
    Uint8List bytes, {
    bool activate = true,
    LibraryPackage? inspected,
  }) async {
    final package = inspected ?? await inspect(bytes);
    final lib = InstalledLibrary.fromPackage(package);
    await _blobs.put(lib.id, bytes);
    final lista = [...state.installed];
    final i = lista.indexWhere((e) => e.id == lib.id);
    if (i >= 0) {
      lista[i] = lib;
    } else {
      lista.add(lib);
    }
    if (isClosed) return lib;
    emit(
      LibraryState(
        installed: List.unmodifiable(lista),
        activeId: activate ? lib.id : state.activeId,
      ),
    );
    await _saveList(lista);
    if (lib.id == kHymnsLibraryId) await migrateLegacyHymnKeys(_prefs);
    if (activate) await _setActive(lib.id);
    return lib;
  }

  /// Apaga o pacote e tira da lista; o progresso fica (D-BIB-REMOVER). Se era
  /// a em uso, passa a ser a primeira que sobrar, ou nenhuma.
  Future<void> remove(String id) async {
    if (state[id] == null) return;
    await _blobs.delete(id);
    final lista = [...state.installed]..removeWhere((e) => e.id == id);
    final eraAtiva = state.activeId == id;
    final activeId = eraAtiva
        ? (lista.isEmpty ? null : lista.first.id)
        : state.activeId;
    if (isClosed) return;
    emit(LibraryState(installed: List.unmodifiable(lista), activeId: activeId));
    await _saveList(lista);
    if (eraAtiva) await _setActive(activeId);
  }

  Future<void> setActive(String id) async {
    if (state[id] == null) throw ArgumentError.value(id, 'id', 'não instalada');
    if (state.activeId == id) return;
    emit(state.copyWith(activeId: id));
    await _setActive(id);
  }

  Future<void> _setActive(String? id) =>
      id == null ? _prefs.remove(activeKey) : _prefs.setString(activeKey, id);

  Future<void> _saveList(List<InstalledLibrary> lista) => _prefs.setString(
    installedKey,
    jsonEncode([for (final lib in lista) lib.toJson()]),
  );

  Uint8List _requireKey() =>
      _publicKey ??
      (throw const LibraryFormatException(
        'Este app foi compilado sem a chave das bibliotecas: não consigo '
        'abrir nenhuma.',
      ));
}
