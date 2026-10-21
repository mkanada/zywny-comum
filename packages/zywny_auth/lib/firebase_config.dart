import 'package:firebase_core/firebase_core.dart';

/// As plataformas onde o app roda (D03).
enum AuthPlatform {
  /// O app Android (o `google_sign_in` e o SDK do Firebase).
  android,

  /// O app na Web (o popup do Firebase).
  web,

  /// O app no Linux (o login pelo navegador do sistema).
  linux,

  /// O app no Windows (o login pelo navegador do sistema).
  windows,

  /// Qualquer outra plataforma: sem login.
  other,
}

/// A configuração do projeto no Firebase (D03).
///
/// Os valores saem do console do Firebase e entram no build por
/// `--dart-define` — fora do git, como as chaves das bibliotecas (o
/// `justfile` de cada app lê `keys/firebase.json` e monta as flags).
///
/// Sem a configuração, o app abre direto, sem o portão: é o caso dos
/// testes, do roteiro `just telas` e de quem compila sem o projeto.
class FirebaseConfig {
  const FirebaseConfig({
    this.apiKey = '',
    this.projectId = '',
    this.messagingSenderId = '',
    this.appIdAndroid = '',
    this.appIdWeb = '',
    this.authDomain = '',
    this.storageBucket = '',
    this.measurementId = '',
    this.googleClientId = '',
    this.googleServerClientId = '',
  });

  /// A configuração deste build: o que o `--dart-define` trouxe.
  static const FirebaseConfig fromEnvironment = FirebaseConfig(
    apiKey: String.fromEnvironment('ZYWNY_FIREBASE_API_KEY'),
    projectId: String.fromEnvironment('ZYWNY_FIREBASE_PROJECT_ID'),
    messagingSenderId: String.fromEnvironment(
      'ZYWNY_FIREBASE_MESSAGING_SENDER_ID',
    ),
    appIdAndroid: String.fromEnvironment('ZYWNY_FIREBASE_APP_ID_ANDROID'),
    appIdWeb: String.fromEnvironment('ZYWNY_FIREBASE_APP_ID_WEB'),
    authDomain: String.fromEnvironment('ZYWNY_FIREBASE_AUTH_DOMAIN'),
    storageBucket: String.fromEnvironment('ZYWNY_FIREBASE_STORAGE_BUCKET'),
    measurementId: String.fromEnvironment('ZYWNY_FIREBASE_MEASUREMENT_ID'),
    googleClientId: String.fromEnvironment('ZYWNY_GOOGLE_CLIENT_ID'),
    googleServerClientId: String.fromEnvironment(
      'ZYWNY_GOOGLE_SERVER_CLIENT_ID',
    ),
  );

  /// Desliga o portão da conta, seja lá qual for a plataforma.
  ///
  /// É o botão de escape do roteiro de telas (`just telas`): com a
  /// configuração do Firebase no build, o app mostraria a tela de entrada e o
  /// roteiro não saberia entrar. **Não** vai para release.
  static const bool authOff = bool.fromEnvironment('ZYWNY_AUTH_OFF');

  /// A chave da Web do projeto (a mesma que vai no `firebase_options.dart`).
  final String apiKey;

  /// O id do projeto no Firebase (ex.: `zywny-prod`).
  final String projectId;

  /// O id do remetente das mensagens (o `sender_id` do `google-services.json`).
  final String messagingSenderId;

  /// O `app_id` do app Android (o do app Web é outro).
  final String appIdAndroid;

  /// O `app_id` do app Web.
  final String appIdWeb;

  /// O domínio de autorização (ex.: `zywny-prod.firebaseapp.com`).
  final String authDomain;

  /// A bucket de arquivos.
  final String storageBucket;

  /// O id da medição (o Analytics; opcional).
  final String measurementId;

  /// O OAuth Client ID do **Desktop** (o do login pelo navegador do
  /// sistema, no Linux e no Windows).
  final String googleClientId;

  /// O `server_client_id` do Google no Android (o OAuth do tipo "Web" do
  /// app Android — é o que o `google_sign_in` usa para pedir o token).
  final String googleServerClientId;

  /// Verdadeiro quando a configuração tem o mínimo do projeto.
  bool get isConfigured =>
      apiKey.isNotEmpty && projectId.isNotEmpty && messagingSenderId.isNotEmpty;

  /// O `app_id` do app registrado para a plataforma.
  String appIdFor(AuthPlatform platform) => switch (platform) {
    AuthPlatform.android => appIdAndroid,
    AuthPlatform.web => appIdWeb,
    AuthPlatform.linux || AuthPlatform.windows || AuthPlatform.other => '',
  };

  /// Verdadeiro quando a configuração cobre a plataforma.
  ///
  /// No Android e na Web o SDK do Firebase precisa do `app_id` do app
  /// registrado; no desktop o login é pelo navegador do sistema e precisa do
  /// OAuth Client ID do "Desktop".
  bool isConfiguredFor(AuthPlatform platform) => switch (platform) {
    AuthPlatform.android => isConfigured && appIdAndroid.isNotEmpty,
    AuthPlatform.web => isConfigured && appIdWeb.isNotEmpty,
    AuthPlatform.linux ||
    AuthPlatform.windows => apiKey.isNotEmpty && googleClientId.isNotEmpty,
    AuthPlatform.other => false,
  };

  /// As opções do SDK do Firebase para a plataforma.
  FirebaseOptions optionsFor(AuthPlatform platform) => FirebaseOptions(
    apiKey: apiKey,
    appId: appIdFor(platform),
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: authDomain.isEmpty ? null : authDomain,
    storageBucket: storageBucket.isEmpty ? null : storageBucket,
    measurementId: measurementId.isEmpty ? null : measurementId,
  );
}
