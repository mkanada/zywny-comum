import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'auth_store.dart';
import 'firebase_config.dart';
import 'firebase_rest_auth_store.dart';
import 'firebase_sdk_auth_store.dart';

/// O caminho do login de cada plataforma (D03).
enum AuthPath {
  /// O SDK do Firebase (Android e Web).
  sdk,

  /// O navegador do sistema e a API REST (Linux e Windows).
  rest,

  /// Sem login.
  none,
}

/// A plataforma em que o app está rodando.
AuthPlatform currentAuthPlatform() {
  if (kIsWeb) return AuthPlatform.web;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return AuthPlatform.android;
    case TargetPlatform.linux:
      return AuthPlatform.linux;
    case TargetPlatform.windows:
      return AuthPlatform.windows;
    default:
      return AuthPlatform.other;
  }
}

/// O caminho do login da plataforma.
///
/// O Linux e o Windows não têm plugin do Firebase: lá o login é pelo
/// navegador do sistema (loopback OAuth) e a troca dos tokens é feita na API
/// REST do Identity Toolkit (D01).
AuthPath authPathFor(AuthPlatform platform) => switch (platform) {
  AuthPlatform.android || AuthPlatform.web => AuthPath.sdk,
  AuthPlatform.linux || AuthPlatform.windows => AuthPath.rest,
  AuthPlatform.other => AuthPath.none,
};

/// Cria o store de autenticação da plataforma (D03).
///
/// Devolve `null` quando o build **não** traz a configuração do Firebase: o
/// app abre direto, sem o portão da conta (D-NEG-SEM-CONTA). É o caso dos
/// testes, do roteiro `just telas` e de quem compila sem `keys/firebase.json`.
///
/// Quando a configuração vem mas o Firebase não sobe (apiKey errada, por
/// exemplo), a mensagem vai para o console e o app também abre sem o portão —
/// um build quebrado não pode trancar o app na tela de entrada.
Future<AuthStore?> createPlatformAuthStore({
  FirebaseConfig? config,
  AuthPlatform? platform,
}) async {
  if (FirebaseConfig.authOff) return null;
  final cfg = config ?? FirebaseConfig.fromEnvironment;
  final target = platform ?? currentAuthPlatform();
  if (!cfg.isConfiguredFor(target)) {
    debugPrint(
      'zywny: este build não tem a configuração do Firebase (D03) — '
      'o app abre sem a conta.',
    );
    return null;
  }
  switch (authPathFor(target)) {
    case AuthPath.none:
      return null;
    case AuthPath.sdk:
      try {
        await Firebase.initializeApp(options: cfg.optionsFor(target));
      } on Object catch (e) {
        debugPrint('zywny: o Firebase não inicializou: $e');
        return null;
      }
      // No Android o `google_sign_in` é reconhecido pelo `applicationId` e
      // pelo SHA-1 da chave; o `server_client_id` é o OAuth do tipo "Web" do
      // app Android. Na Web o login é o popup do próprio Firebase.
      return FirebaseSdkAuthStore(
        googleServerClientId: cfg.googleServerClientId,
      );
    case AuthPath.rest:
      return FirebaseRestAuthStore(
        apiKey: cfg.apiKey,
        clientId: cfg.googleClientId,
      );
  }
}
