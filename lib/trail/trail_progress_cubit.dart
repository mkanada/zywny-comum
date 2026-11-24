// J03 — Guarda o progresso de cada trilha (`TrailProgressCubit`, BL10: era o
// `TrailProgressStore`, um `ChangeNotifier`). O modelo (`TrailProgress`, as
// etapas e o `resume`) continua em `trail_progress.dart`.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import 'package:zywny_library/library_keys.dart';
import 'package:zywny_library/piece.dart' show kHymnsLibraryId;

import 'package:zywny_music/transposition.dart';

import 'trail_progress.dart';

/// O que o store guarda: o tom da biblioteca em uso e a trilha de cada hino já
/// lida. Imutável: cada gravação põe um mapa novo.
class TrailProgressState extends Equatable {
  const TrailProgressState({
    this.libraryId = kHymnsLibraryId,
    this.byId = const {},
  });

  /// A biblioteca cujas trilhas estão em [byId] (as chaves dependem dela).
  final String libraryId;

  /// O progresso de cada id de progresso (`progressIdFor`) lido ou gravado.
  final Map<String, TrailProgress> byId;

  TrailProgressState copyWith({
    String? libraryId,
    Map<String, TrailProgress>? byId,
  }) => TrailProgressState(
    libraryId: libraryId ?? this.libraryId,
    byId: byId ?? this.byId,
  );

  @override
  List<Object?> get props => [libraryId, byId];
}

/// Guarda uma trilha por música **e por tom** (`trail_<biblioteca>_<id>`, com
/// `'v': 1`), com `done`/`total` junto para a biblioteca (J09). Avisa quem
/// escuta a cada mudança — a biblioteca refaz a linha da música ao voltar da
/// partitura.
///
/// Os ids que a classe recebe são **ids de progresso** ([progressIdFor]): o da
/// música, no tom original (as chaves de antes da fase Q), ou com o sufixo do
/// tom transposto — cada tom tem a sua trilha (D-TRP-PROGRESSO).
///
/// Vale para uma biblioteca por vez: [load] diz qual (a em uso).
class TrailProgressCubit extends Cubit<TrailProgressState> {
  TrailProgressCubit({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync(),
      super(const TrailProgressState());

  final SharedPreferencesAsync _prefs;

  /// Os ids que já foram procurados nas preferências (achados ou não), para
  /// [loadMissing] não reler os que não têm trilha. É cache de leitura, não
  /// algo que a tela mostre, por isso não está no estado.
  final Set<String> _looked = {};

  String get libraryId => state.libraryId;

  /// O progresso de [id] no estado (vazio se não há trilha).
  TrailProgress operator [](String id) => state.byId[id] ?? TrailProgress.empty;

  /// Garante a música na memória (uma chave só) — a tela usa isto ao abrir a
  /// partitura; o `load()` em lote é para a biblioteca (J09).
  Future<TrailProgress> ensureLoaded(String id) async {
    _looked.add(id);
    try {
      final text = await _prefs.getString(trailKeyFor(state.libraryId, id));
      if (text != null) {
        _put(
          id,
          TrailProgress.fromJson(jsonDecode(text) as Map<String, dynamic>),
        );
      }
    } on Object {
      _drop(id);
    }
    return this[id];
  }

  /// Resumo pronto para a biblioteca (J09): sem montar nenhum plano.
  ({int done, int total, int skipped, bool completed, TrailResume? resume})
  summary(String id) {
    final p = state.byId[id] ?? TrailProgress.empty;
    return (
      done: p.done,
      total: p.total,
      skipped: p.skipped,
      completed: p.finalApproved,
      resume: p.resume,
    );
  }

  /// Lê a trilha de cada uma das [ids] de [libraryId] (a que ficou em uso,
  /// se omitido) — as músicas do catálogo, não um intervalo fixo.
  Future<void> load(Iterable<String> ids, [String? libraryId]) async {
    final library = libraryId ?? state.libraryId;
    _looked.clear();
    final read = await _readAll(ids, library);
    if (isClosed) return;
    emit(TrailProgressState(libraryId: library, byId: read));
  }

  /// Lê só as [ids] que ainda não foram procuradas: a biblioteca troca o tom
  /// em uso de uma música (chave geral, escolha na partitura) e precisa da
  /// trilha do tom novo sem reler o catálogo inteiro.
  Future<void> loadMissing(Iterable<String> ids) async {
    final missing = [
      for (final id in ids)
        if (!_looked.contains(id)) id,
    ];
    if (missing.isEmpty) return;
    final read = await _readAll(missing, state.libraryId);
    if (isClosed) return;
    emit(state.copyWith(byId: {...state.byId, ...read}));
  }

  /// Lê as [ids] da biblioteca [library]; só devolve as que tinham trilha
  /// legível (o resto fica como estava).
  Future<Map<String, TrailProgress>> _readAll(
    Iterable<String> ids,
    String library,
  ) async {
    final read = <String, TrailProgress>{};
    for (final id in ids) {
      _looked.add(id);
      try {
        final text = await _prefs.getString(trailKeyFor(library, id));
        if (text == null) continue;
        read[id] = TrailProgress.fromJson(
          jsonDecode(text) as Map<String, dynamic>,
        );
      } on Object {
        // JSON estragado: trilha vazia, sem exceção (padrão do piece_progress).
        continue;
      }
    }
    return read;
  }

  /// Os tons em que [pieceId] tem trilha começada (alguma etapa feita): o
  /// original e os `<id>@<intervalo>` que existem nas preferências. É o que a
  /// tela da música mostra em "Também estudada". O original vem primeiro; os
  /// outros, por intervalo.
  Future<List<StudiedTone>> studiedTones(String pieceId) async {
    final library = state.libraryId;
    final base = trailKeyFor(library, pieceId);
    final found = <StudiedTone>[];
    try {
      final keys = await _prefs.getKeys();
      for (final key in keys) {
        if (key != base && !key.startsWith('$base@')) continue;
        final progressId = key.substring('trail_${library}_'.length);
        final tone = toneOfProgressId(progressId);
        if (key != base && tone == null) continue;
        final text = await _prefs.getString(key);
        if (text == null) continue;
        final progress = TrailProgress.fromJson(
          jsonDecode(text) as Map<String, dynamic>,
        );
        if (progress.done > 0) {
          found.add((transposition: tone, progress: progress));
        }
      }
    } on Object {
      // Preferência estragada: lista o que deu para ler.
    }
    found.sort(
      (a, b) => (a.transposition?.interval ?? '').compareTo(
        b.transposition?.interval ?? '',
      ),
    );
    return found;
  }

  /// Trocar [pieceId] do tom [from] para o tom [to] (`null` = o original)
  /// deixa para trás uma trilha em andamento? É quando há etapa feita em
  /// [from] e nenhuma em [to]: a tela pergunta antes ("Em Dó a trilha começa
  /// do zero. A do tom original fica guardada.").
  Future<bool> toneChangeStartsOver(
    String pieceId,
    Transposition? from,
    Transposition? to,
  ) async {
    if (from == to) return false;
    final current = await ensureLoaded(progressIdFor(pieceId, from));
    if (current.done == 0) return false;
    final target = await ensureLoaded(progressIdFor(pieceId, to));
    return target.done == 0;
  }

  /// Grava o progresso de [id] (na memória, e avisa, na hora) e depois o manda
  /// às preferências.
  Future<void> save(String id, TrailProgress progress) {
    _looked.add(id);
    _put(id, progress);
    return _prefs.setString(
      trailKeyFor(state.libraryId, id),
      jsonEncode(progress.toJson()),
    );
  }

  Future<void> reset(String id) {
    _drop(id);
    return _prefs.remove(trailKeyFor(state.libraryId, id));
  }

  /// Põe [progress] de [id] no estado. Depois do `close`, não avisa.
  void _put(String id, TrailProgress progress) {
    if (isClosed) return;
    emit(state.copyWith(byId: {...state.byId, id: progress}));
  }

  /// Tira [id] do estado (se estava lá). Depois do `close`, não faz nada.
  void _drop(String id) {
    if (isClosed || !state.byId.containsKey(id)) return;
    emit(state.copyWith(byId: {...state.byId}..remove(id)));
  }
}
