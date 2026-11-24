import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import 'package:zywny_music/transposition.dart';

import 'library_keys.dart';
import 'piece.dart' show kHymnsLibraryId;

/// O que o app sabe do estudo de um hino: quando foi aberto pela última vez
/// e a melhor precisão de um treino avaliado (tempo real).
///
/// Com a transposição (fase Q) cada tom tem a sua pontuação, numa entrada com
/// o id do tom ([progressIdFor]); só a entrada do id puro tem [lastOpened] —
/// "última aberta" é por música — e [transpose].
@immutable
class PieceProgress {
  const PieceProgress({this.lastOpened, this.bestScore, this.transpose});

  final DateTime? lastOpened;

  /// 0–100, ou `null` se nenhum treino avaliado terminou ainda.
  final int? bestScore;

  /// A escolha de transposição **da música** (`PieceSettings.transpose`: um
  /// intervalo, `kTransposeNone`, ou `null` se a pessoa não escolheu), guardada
  /// aqui para a biblioteca saber o tom em uso de cada música sem ler as
  /// configurações de todas. Só a entrada do id puro a tem.
  final String? transpose;
}

/// O progresso por música da biblioteca em uso. Imutável: o mapa é outro a
/// cada mudança. As consultas ([], [forTone], [transposeChoice],
/// [lastOpenedId]) leem daqui; quem mostra o progresso escuta o estado.
class PieceProgressState extends Equatable {
  const PieceProgressState({
    this.libraryId = kHymnsLibraryId,
    this.byId = const {},
  });

  /// A biblioteca de que é este progresso (a que [PieceProgressCubit.load]
  /// leu por último).
  final String libraryId;

  /// id → estudo.
  final Map<String, PieceProgress> byId;

  PieceProgress? operator [](String id) => byId[id];

  /// O estudo de [pieceId] no tom [transposition] (`null` = o original): a
  /// última abertura é da música; a pontuação, do tom.
  PieceProgress? forTone(String pieceId, Transposition? transposition) {
    final piece = byId[pieceId];
    final score = byId[progressIdFor(pieceId, transposition)]?.bestScore;
    if (piece == null && score == null) return null;
    return PieceProgress(
      lastOpened: piece?.lastOpened,
      bestScore: score,
      transpose: piece?.transpose,
    );
  }

  /// A escolha de transposição guardada de [pieceId] (ver
  /// [PieceProgress.transpose]); `null` se a pessoa nunca escolheu ou a música
  /// nunca foi aberta.
  String? transposeChoice(String pieceId) => byId[pieceId]?.transpose;

  /// Id da música aberta mais recentemente, ou `null` se nenhuma.
  String? get lastOpenedId {
    String? best;
    DateTime? bestAt;
    byId.forEach((id, p) {
      final at = p.lastOpened;
      if (at != null && (bestAt == null || at.isAfter(bestAt!))) {
        best = id;
        bestAt = at;
      }
    });
    return best;
  }

  @override
  List<Object?> get props => [libraryId, byId];
}

/// Progresso por música de uma biblioteca, guardado num só JSON por
/// biblioteca em [SharedPreferencesAsync] (`lib_progress_<biblioteca>`, mapa
/// id → `{t, s}`). Avisa quem escuta a cada mudança — a biblioteca reordena
/// "Recentes" e "Pontuação" e refaz o cartão "Continuar".
///
/// Vale para uma biblioteca por vez: [load] diz qual (a em uso); trocar de
/// biblioteca é chamar [load] de novo.
class PieceProgressCubit extends Cubit<PieceProgressState> {
  PieceProgressCubit({SharedPreferencesAsync? prefs, DateTime Function()? now})
    : _prefs = prefs ?? SharedPreferencesAsync(),
      _now = now ?? DateTime.now,
      super(const PieceProgressState());

  final SharedPreferencesAsync _prefs;
  final DateTime Function() _now;

  /// Lê o progresso de [libraryId] (a que ficou em uso, se omitido).
  Future<void> load([String? libraryId]) async {
    final lib = libraryId ?? state.libraryId;
    final byId = <String, PieceProgress>{};
    final text = await _prefs.getString(progressKeyFor(lib));
    if (text != null) {
      try {
        final map = jsonDecode(text) as Map<String, dynamic>;
        map.forEach((id, value) {
          final v = value as Map<String, dynamic>;
          final at = v['t'] as int?;
          byId[id] = PieceProgress(
            lastOpened: at == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(at),
            bestScore: v['s'] as int?,
            transpose: v['tr'] as String?,
          );
        });
      } on Object {
        // JSON estragado: começa do zero em vez de travar a biblioteca.
        byId.clear();
      }
    }
    if (isClosed) return;
    emit(PieceProgressState(libraryId: lib, byId: Map.unmodifiable(byId)));
  }

  /// Marca [id] (a música, não o tom) como aberta agora, com a escolha de
  /// transposição que ela tem ([transpose], ver [PieceProgress.transpose]).
  Future<void> markOpened(String id, {String? transpose}) => _mudar(
    id,
    PieceProgress(
      lastOpened: _now(),
      bestScore: state[id]?.bestScore,
      transpose: transpose,
    ),
  );

  /// A escolha de transposição de [id] mudou (a pessoa transpôs, ou voltou ao
  /// original, com a música aberta).
  Future<void> setTranspose(String id, String? transpose) {
    final current = state[id];
    if ((current?.transpose) == transpose) return Future.value();
    return _mudar(
      id,
      PieceProgress(
        lastOpened: current?.lastOpened,
        bestScore: current?.bestScore,
        transpose: transpose,
      ),
    );
  }

  /// Guarda [score] (0–100) se for a melhor do tom até aqui. [id] é o id do
  /// progresso ([progressIdFor]): o da música no tom original, ou com o
  /// sufixo do tom transposto.
  Future<void> recordScore(String id, int score) {
    final current = state[id];
    final best = current?.bestScore;
    if (best != null && best >= score) return Future.value();
    return _mudar(
      id,
      PieceProgress(
        // Pontuar não é abrir: só [markOpened] marca a música como aberta. Se
        // a nota marcasse, a versão simplificada (`<id>.s`), que não está no
        // catálogo, viraria a "última aberta" e o "Continuar" sumiria.
        lastOpened: current?.lastOpened,
        bestScore: score,
        transpose: current?.transpose,
      ),
    );
  }

  /// Troca a entrada de [id]: emite o estado novo e só então grava (como a
  /// memória mudava antes do aviso e da gravação).
  Future<void> _mudar(String id, PieceProgress valor) {
    final novo = PieceProgressState(
      libraryId: state.libraryId,
      byId: {...state.byId, id: valor},
    );
    emit(novo);
    return _gravar(novo);
  }

  Future<void> _gravar(PieceProgressState estado) => _prefs.setString(
    progressKeyFor(estado.libraryId),
    jsonEncode({
      for (final e in estado.byId.entries)
        e.key: {
          if (e.value.lastOpened case final at?) 't': at.millisecondsSinceEpoch,
          's': ?e.value.bestScore,
          'tr': ?e.value.transpose,
        },
    }),
  );
}
