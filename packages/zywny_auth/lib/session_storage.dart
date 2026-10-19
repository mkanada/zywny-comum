import 'package:shared_preferences/shared_preferences.dart';

import 'auth_user.dart';
import 'session_freshness.dart';

/// A sessão guardada no aparelho — a mesma nos dois caminhos de login
/// (SDK no Android/Web, REST no desktop). Vive nas preferências do sistema,
/// para o app abrir já conectado depois de fechado.
class SessionStorage {
  SessionStorage({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const String uidKey = 'auth_uid';
  static const String emailKey = 'auth_email';
  static const String displayNameKey = 'auth_display_name';
  static const String photoUrlKey = 'auth_photo_url';
  static const String providerIdKey = 'auth_provider_id';
  static const String idTokenKey = 'auth_id_token';
  static const String refreshTokenKey = 'auth_refresh_token';
  static const String idTokenExpiresAtKey = 'auth_id_token_expires_at_ms';
  static const String nicknameKey = 'auth_nickname';

  final SharedPreferencesAsync _prefs;

  /// Lê a sessão guardada, ou `null` se não houver.
  Future<AuthUser?> read() async {
    final uid = await _prefs.getString(uidKey);
    final idToken = await _prefs.getString(idTokenKey);
    if (uid == null || uid.isEmpty || idToken == null || idToken.isEmpty) {
      return null;
    }
    return AuthUser(
      uid: uid,
      providerId:
          await _prefs.getString(providerIdKey) ?? SocialProvider.google.id,
      idToken: idToken,
      email: await _prefs.getString(emailKey),
      displayName: await _prefs.getString(displayNameKey),
      photoUrl: await _prefs.getString(photoUrlKey),
      refreshToken: await _prefs.getString(refreshTokenKey),
      idTokenExpiresAt: _fromMillis(await _prefs.getInt(idTokenExpiresAtKey)),
      lastServerCheckAt: _fromMillis(
        await _prefs.getInt(SessionFreshness.lastVerifiedKey),
      ),
      nickname: await _prefs.getString(nicknameKey),
    );
  }

  /// Grava a sessão.
  Future<void> write(AuthUser user) async {
    await _prefs.setString(uidKey, user.uid);
    await _prefs.setString(providerIdKey, user.providerId);
    await _prefs.setString(idTokenKey, user.idToken);
    await _setOrRemove(emailKey, user.email);
    await _setOrRemove(displayNameKey, user.displayName);
    await _setOrRemove(photoUrlKey, user.photoUrl);
    await _setOrRemove(refreshTokenKey, user.refreshToken);
    await _setOrRemove(nicknameKey, user.nickname);
    await _setOrRemoveMillis(idTokenExpiresAtKey, user.idTokenExpiresAt);
    await _setOrRemoveMillis(
      SessionFreshness.lastVerifiedKey,
      user.lastServerCheckAt,
    );
  }

  /// Apaga tudo que é da sessão (usuário sai ou apaga a conta).
  Future<void> clear() async {
    await _prefs.remove(uidKey);
    await _prefs.remove(providerIdKey);
    await _prefs.remove(idTokenKey);
    await _prefs.remove(emailKey);
    await _prefs.remove(displayNameKey);
    await _prefs.remove(photoUrlKey);
    await _prefs.remove(refreshTokenKey);
    await _prefs.remove(nicknameKey);
    await _prefs.remove(idTokenExpiresAtKey);
    await _prefs.remove(SessionFreshness.lastVerifiedKey);
  }

  Future<void> _setOrRemove(String key, String? value) =>
      value == null ? _prefs.remove(key) : _prefs.setString(key, value);

  Future<void> _setOrRemoveMillis(String key, DateTime? value) => value == null
      ? _prefs.remove(key)
      : _prefs.setInt(key, value.millisecondsSinceEpoch);

  static DateTime? _fromMillis(int? millis) =>
      millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}

/// Troca o apelido da pessoa guardada no aparelho (D-NEG-PRIVACIDADE). O
/// apelido é do Zywny, não o nome de cadastro do provedor.
Future<AuthUser> saveNickname(
  SessionStorage storage,
  AuthUser user,
  String nickname,
) async {
  final trimmed = nickname.trim();
  final updated = user.copyWith(nickname: trimmed.isEmpty ? null : trimmed);
  await storage.write(updated);
  return updated;
}
