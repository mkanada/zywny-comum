/// A autenticação do zywny (fase D, D01): o contrato, os dois caminhos de
/// login (SDK do Firebase no Android/Web, REST + loopback no desktop), a
/// regra dos 7 dias sem rede e o store de mentira dos testes.
library;

export 'auth_state.dart';
export 'auth_store.dart';
export 'auth_user.dart';
export 'fake_auth_store.dart';
export 'firebase_rest_auth_store.dart';
export 'firebase_sdk_auth_store.dart';
export 'id_token.dart';
export 'loopback_oauth.dart';
export 'session_freshness.dart';
export 'session_storage.dart';
