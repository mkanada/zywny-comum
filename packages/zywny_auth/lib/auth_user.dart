import 'package:flutter/foundation.dart';

/// Os provedores de login social que o app oferece (D-NEG-AUTH: Google e
/// outras redes sociais, no plano gratuito do Firebase).
enum SocialProvider {
  google('google.com', 'Google'),
  apple('apple.com', 'Apple'),
  microsoft('microsoft.com', 'Microsoft'),
  github('github.com', 'GitHub'),
  facebook('facebook.com', 'Facebook');

  const SocialProvider(this.id, this.label);

  /// O `providerId` do Firebase (e o do OAuth do Google).
  final String id;

  /// O nome que aparece no botão.
  final String label;
}

/// A pessoa conectada: quem é, com que tokens, e quando o servidor foi visto
/// pela última vez — é esse instante que conta para a regra dos 7 dias sem
/// rede (D-NEG-OFFLINE).
@immutable
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.providerId,
    required this.idToken,
    this.email,
    this.displayName,
    this.photoUrl,
    this.refreshToken,
    this.idTokenExpiresAt,
    this.lastServerCheckAt,
    this.nickname,
  });

  /// O identificador da conta no Firebase. É o mesmo nos dois apps
  /// (D-NEG-AUTH) e é o que amarra as licenças dos pacotes (D04).
  final String uid;

  /// De onde veio a sessão: `google.com`, `apple.com`…
  final String providerId;

  /// O `idToken` do Firebase: vale uma hora e é renovado por [refreshToken].
  final String idToken;

  final String? email;
  final String? displayName;
  final String? photoUrl;

  /// O `refreshToken`: com ele o app renova a sessão sem pedir login outra
  /// vez.
  final String? refreshToken;

  /// Quando o [idToken] expira.
  final DateTime? idTokenExpiresAt;

  /// A última vez que o servidor respondeu. A regra dos 7 dias conta a
  /// partir daqui (D-NEG-OFFLINE).
  final DateTime? lastServerCheckAt;

  /// O apelido escolhido dentro do Zywny (D-NEG-PRIVACIDADE). Não é o nome
  /// de cadastro do provedor: fica só no aparelho.
  final String? nickname;

  /// O mesmo usuário com o apelido trocado.
  AuthUser copyWith({
    String? uid,
    String? providerId,
    String? idToken,
    String? email,
    String? displayName,
    String? photoUrl,
    String? refreshToken,
    DateTime? idTokenExpiresAt,
    DateTime? lastServerCheckAt,
    String? nickname,
  }) {
    return AuthUser(
      uid: uid ?? this.uid,
      providerId: providerId ?? this.providerId,
      idToken: idToken ?? this.idToken,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      refreshToken: refreshToken ?? this.refreshToken,
      idTokenExpiresAt: idTokenExpiresAt ?? this.idTokenExpiresAt,
      lastServerCheckAt: lastServerCheckAt ?? this.lastServerCheckAt,
      nickname: nickname ?? this.nickname,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          other.uid == uid &&
          other.providerId == providerId &&
          other.idToken == idToken &&
          other.email == email &&
          other.displayName == displayName &&
          other.photoUrl == photoUrl &&
          other.refreshToken == refreshToken &&
          other.idTokenExpiresAt == idTokenExpiresAt &&
          other.lastServerCheckAt == lastServerCheckAt &&
          other.nickname == nickname;

  @override
  int get hashCode => Object.hash(
    uid,
    providerId,
    idToken,
    email,
    displayName,
    photoUrl,
    refreshToken,
    idTokenExpiresAt,
    lastServerCheckAt,
    nickname,
  );

  @override
  String toString() => 'AuthUser($uid, $providerId)';
}
