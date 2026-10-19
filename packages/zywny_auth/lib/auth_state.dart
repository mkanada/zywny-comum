import 'package:flutter/foundation.dart';

import 'auth_user.dart';

/// Em que situação a sessão está (D01).
enum AuthStatus {
  /// Ainda não se sabe: o app está restoring a sessão guardada.
  initializing,

  /// Ninguém conectado.
  unauthenticated,

  /// Conectado e em dia.
  authenticated,

  /// A sessão guardada passou dos 7 dias sem rede (ou o relógio do aparelho
  /// andou para trás): o app precisa falar com o servidor antes de deixar
  /// entrar (D-NEG-OFFLINE).
  offlineExpired,
}

/// O estado da autenticação, com a pessoa conectada (quando há) e uma
/// mensagem de erro em português, para a tela mostrar.
@immutable
class AuthState {
  const AuthState._({required this.status, this.user, this.errorMessage});

  /// Ainda carregando.
  const AuthState.initializing() : this._(status: AuthStatus.initializing);

  /// Sem ninguém conectado. [errorMessage] explica por quê (quando o erro é
  /// o motivo de ter saído).
  const AuthState.unauthenticated({String? errorMessage})
    : this._(status: AuthStatus.unauthenticated, errorMessage: errorMessage);

  /// Conectado. [errorMessage] é um aviso que não impede o uso (por exemplo,
  /// a rede caiu na hora de renovar o token).
  const AuthState.authenticated(AuthUser user, {String? errorMessage})
    : this._(
        status: AuthStatus.authenticated,
        user: user,
        errorMessage: errorMessage,
      );

  /// A sessão guardada não vale mais sem falar com o servidor.
  const AuthState.offlineExpired({required AuthUser user, String? errorMessage})
    : this._(
        status: AuthStatus.offlineExpired,
        user: user,
        errorMessage: errorMessage,
      );

  final AuthStatus status;

  /// Quem está conectado (nos estados em que há alguém).
  final AuthUser? user;

  /// O erro ou aviso, em português.
  final String? errorMessage;

  /// Verdadeiro quando o app pode ser usado (a tela de entrada some).
  bool get isAuthenticated => status == AuthStatus.authenticated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState &&
          other.status == status &&
          other.user == user &&
          other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(status, user, errorMessage);

  @override
  String toString() => 'AuthState($status, $user)';
}

/// Um erro de autenticação, com a mensagem que a tela mostra.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
