// D03 — a configuração do projeto no Firebase e a escolha do caminho de
// login de cada plataforma.
//
// O caminho do SDK (Android e Web) precisa do Firebase de verdade, que só
// existe depois que o projeto é criado no console: aqui se confere a
// decisão (qual caminho, o que falta na configuração) e o store do desktop,
// que não depende de rede para existir.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zywny_auth/zywny_auth.dart';

/// A configuração completa de um projeto (o que o console devolve).
const _completa = FirebaseConfig(
  apiKey: 'AIza-chave',
  projectId: 'zywny-prod',
  messagingSenderId: '123456789',
  appIdAndroid: '1:123456789:android:aaa',
  appIdWeb: '1:123456789:web:bbb',
  authDomain: 'zywny-prod.firebaseapp.com',
  storageBucket: 'zywny-prod.appspot.com',
  measurementId: 'G-XXX',
  googleClientId: 'desktop.apps.googleusercontent.com',
  googleServerClientId: 'android.apps.googleusercontent.com',
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('a configuração do build (D03)', () {
    test('sem as flags, não há configuração', () {
      // Neste build não há --dart-define: é o caso de quem compila sem
      // keys/firebase.json. (Com as flags, a configuração tem de estar toda.)
      if (const String.fromEnvironment('ZYWNY_FIREBASE_API_KEY').isEmpty) {
        expect(FirebaseConfig.fromEnvironment.isConfigured, isFalse);
        expect(
          FirebaseConfig.fromEnvironment.isConfiguredFor(AuthPlatform.android),
          isFalse,
        );
      } else {
        expect(FirebaseConfig.fromEnvironment.isConfigured, isTrue);
      }
    });

    test('a configuração do build sai das flags', () {
      const config = FirebaseConfig(
        apiKey: 'AIza-chave',
        projectId: 'zywny-prod',
        messagingSenderId: '123456789',
        appIdAndroid: '1:1:android:aaa',
        appIdWeb: '1:1:web:bbb',
      );
      expect(config.isConfigured, isTrue);
      expect(config.isConfiguredFor(AuthPlatform.android), isTrue);
      expect(config.isConfiguredFor(AuthPlatform.web), isTrue);
      // No desktop o login é pelo navegador do sistema: precisa do OAuth
      // Client ID do "Desktop", não do app_id.
      expect(config.isConfiguredFor(AuthPlatform.linux), isFalse);
      expect(
        const FirebaseConfig(
          apiKey: 'AIza-chave',
          googleClientId: 'desktop.apps.googleusercontent.com',
        ).isConfiguredFor(AuthPlatform.windows),
        isTrue,
      );
    });

    test('as opções do SDK levam o app_id da plataforma', () {
      expect(
        _completa.optionsFor(AuthPlatform.android).appId,
        '1:123456789:android:aaa',
      );
      expect(
        _completa.optionsFor(AuthPlatform.web).appId,
        '1:123456789:web:bbb',
      );
      final options = _completa.optionsFor(AuthPlatform.web);
      expect(options.apiKey, 'AIza-chave');
      expect(options.projectId, 'zywny-prod');
      expect(options.messagingSenderId, '123456789');
      expect(options.authDomain, 'zywny-prod.firebaseapp.com');
      expect(options.storageBucket, 'zywny-prod.appspot.com');
    });
  });

  group('o caminho do login (D03)', () {
    test('cada plataforma tem o seu caminho', () {
      expect(authPathFor(AuthPlatform.android), AuthPath.sdk);
      expect(authPathFor(AuthPlatform.web), AuthPath.sdk);
      expect(authPathFor(AuthPlatform.linux), AuthPath.rest);
      expect(authPathFor(AuthPlatform.windows), AuthPath.rest);
      expect(authPathFor(AuthPlatform.other), AuthPath.none);
    });
  });

  group('o store da plataforma (D03)', () {
    test('sem a configuração, o app abre sem o portão', () async {
      expect(
        await createPlatformAuthStore(config: const FirebaseConfig()),
        isNull,
      );
      expect(
        await createPlatformAuthStore(
          config: const FirebaseConfig(),
          platform: AuthPlatform.linux,
        ),
        isNull,
      );
    });

    test('no desktop, o store é o do navegador do sistema', () async {
      final store = await createPlatformAuthStore(
        config: _completa,
        platform: AuthPlatform.linux,
      );
      expect(store, isA<FirebaseRestAuthStore>());
      final windows = await createPlatformAuthStore(
        config: _completa,
        platform: AuthPlatform.windows,
      );
      expect(windows, isA<FirebaseRestAuthStore>());
    });

    test('numa plataforma sem login, não há store', () async {
      expect(
        await createPlatformAuthStore(
          config: _completa,
          platform: AuthPlatform.other,
        ),
        isNull,
      );
    });
  });
}
