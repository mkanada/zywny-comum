import 'package:zywny_music/transposition.dart';

/// Chaves de `shared_preferences` do que o app guarda por biblioteca e por
/// música (docs/plano/B00). Remover uma biblioteca não apaga nenhuma delas
/// (D-BIB-REMOVER): reinstalar recupera o progresso.
String progressKeyFor(String libraryId) => 'lib_progress_$libraryId';

String pieceSettingsKeyFor(String libraryId, String pieceId) =>
    'piece_settings_${libraryId}_$pieceId';

/// A versão (completa ou simplificada) em que a música abre, lembrada por
/// música.
String pieceVersionKeyFor(String libraryId, String pieceId) =>
    'piece_version_${libraryId}_$pieceId';

String trailKeyFor(String libraryId, String progressId) =>
    'trail_${libraryId}_$progressId';

/// O id sob o qual se guarda o progresso (trilha e pontuação) de [pieceId] no
/// tom em uso (fase Q, D-TRP-PROGRESSO): o tom original, `null`, mantém o id da
/// música — as chaves de antes da fase Q continuam valendo, sem migração —, e
/// um tom transposto acrescenta o intervalo (`001@-m3`). **É a única forma de
/// montar esse id**: ninguém concatena à mão.
String progressIdFor(String pieceId, Transposition? transposition) =>
    transposition == null
    ? pieceId
    : '$pieceId$_toneMark${transposition.interval}';

/// A música de um id de progresso: tira o sufixo de tom, se houver.
String pieceIdOfProgressId(String progressId) {
  final at = progressId.indexOf(_toneMark);
  return at < 0 ? progressId : progressId.substring(0, at);
}

/// O tom de um id de progresso: `null` no original (e num sufixo que não é um
/// intervalo, que não deveria existir).
Transposition? toneOfProgressId(String progressId) {
  final at = progressId.indexOf(_toneMark);
  return at < 0
      ? null
      : Transposition.parse(progressId.substring(at + _toneMark.length));
}

const String _toneMark = '@';
