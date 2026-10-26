import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'diag_storage.dart';

export 'diag_storage.dart';

/// Uma sessão do log: o período em que o aluno ficou num exercício, numa
/// música ou numa aula. Quem a abre ([DiagLog.beginSession]) a fecha
/// ([DiagLog.endSession]).
class DiagSession {
  DiagSession._(this.key, this.kind, this.name, this.start);

  /// Nome do arquivo (`s00007`).
  final String key;

  /// `exercicio`, `musica`, `aula`…
  final String kind;

  /// Qual exercício/música/aula (`34d`, `hino 001`…).
  final String name;
  final DateTime start;
}

/// Um arquivo do log, como vai para o relatório.
class DiagLogFile {
  const DiagLogFile(this.name, this.text);

  final String name;
  final String text;
}

/// Registro de diagnóstico rotativo, sempre ligado, dos dois apps.
///
/// As linhas vão para a **sessão** aberta mais recente (exercício, música,
/// aula; ver [beginSession]); sem sessão, ou se for um erro, vão também para
/// `app`. Ficam as [keepEnded] últimas sessões encerradas mais as abertas
/// (inclusive as de execuções anteriores do app: se ele travou, o relatório
/// da próxima abertura ainda leva a sessão do travamento). O aluno não mexe
/// em nada: ao reportar um bug (`BugReportScope`, no `zywny_comum`), o
/// relatório leva esses arquivos.
///
/// Nos apps nativos são arquivos na pasta do app (`diag/`; no Android, a
/// externa, legível com `adb pull`). Cada linha é gravada e descarregada na
/// hora (`flushSync`). Na Web (sem disco), ficam na memória. Antes de [init]
/// (os testes) tudo isto é um no-op.
class DiagLog {
  DiagLog._();

  /// Quantas sessões já encerradas ficam guardadas.
  static const keepEnded = 2;

  static DiagStorage? _storage;
  static final Stopwatch _clock = Stopwatch();
  static int _seq = 0;
  static final List<DiagSession> _open = [];
  static final List<String> _ended = [];
  static final Map<String, Object? Function()> _providers = {};
  static final Map<String, String Function()> _attachments = {};
  static final List<VoidCallback> _freezeHooks = [];
  static bool _handlersInstalled = false;

  /// Abre o armazenamento e liga a captura de erros, de `debugPrint` e do
  /// ciclo de vida. Chamar uma vez, logo depois de
  /// `WidgetsFlutterBinding.ensureInitialized`.
  ///
  /// [storage] e [installHandlers] são dos testes.
  static Future<void> init({
    DiagStorage? storage,
    bool installHandlers = true,
  }) async {
    if (_storage != null) return;
    try {
      _storage = storage ?? await _defaultStorage();
    } catch (e) {
      debugPrint('DiagLog: não abriu o armazenamento: $e');
      return;
    }
    final store = _storage!;
    // O que sobrou de execuções anteriores conta como sessão encerrada.
    final old = store.keys().where(_isSessionKey).toList()..sort();
    for (final k in old) {
      if (_seqOf(k) > _seq) _seq = _seqOf(k);
    }
    _ended
      ..clear()
      ..addAll(old);
    _trim();
    _clock.start();
    log(
      'app',
      '==== nova execução ${DateTime.now().toIso8601String()} '
          '(${defaultTargetPlatform.name}${kIsWeb ? ', web' : ''}) ====',
    );
    if (installHandlers) _installHandlers();
    if (installHandlers) {
      // Com uma sessão aberta (exercício, música, aula), o estado inteiro vai
      // para o log de tempos em tempos: quem reporta nem sempre sabe dizer
      // quando a coisa começou a andar errado.
      _beat?.cancel();
      _beat = Timer.periodic(heartbeat, (_) {
        if (_open.isNotEmpty) logState('periódico');
      });
    }
  }

  /// De quanto em quanto tempo o [logState] automático roda.
  static const heartbeat = Duration(seconds: 10);
  static Timer? _beat;

  static Future<DiagStorage> _defaultStorage() async {
    if (kIsWeb) return MemoryDiagStorage();
    var dir = defaultTargetPlatform == TargetPlatform.android
        ? await getExternalStorageDirectory()
        : null;
    dir ??= await getApplicationSupportDirectory();
    return FileDiagStorage('${dir.path}/diag');
  }

  static void _installHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      log(
        'erro',
        'FlutterError: ${details.exceptionAsString()}\n${details.stack}',
      );
      previousOnError?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      log('erro', 'não tratado: $error\n$stack');
      return false;
    };
    final previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) log('print', message);
      previousPrint(message, wrapWidth: wrapWidth);
    };
    AppLifecycleListener(
      onStateChange: (s) => log('app', 'ciclo de vida: ${s.name}'),
    );
  }

  /// Só os testes: volta ao estado de antes de [init].
  @visibleForTesting
  static void reset() {
    _beat?.cancel();
    _beat = null;
    _storage = null;
    _clock
      ..stop()
      ..reset();
    _seq = 0;
    _open.clear();
    _ended.clear();
    _providers.clear();
    _attachments.clear();
    _freezeHooks.clear();
  }

  static bool get enabled => _storage != null;

  static bool _isSessionKey(String k) => RegExp(r'^s\d+$').hasMatch(k);
  static int _seqOf(String k) => int.parse(k.substring(1));

  /// Uma linha: hora do relógio, ms desde a abertura do log, etiqueta e
  /// texto. Vai para a sessão aberta mais recente (e, se a etiqueta é
  /// `erro` ou não há sessão, para `app`). Seguro de chamar antes de [init].
  static void log(String tag, String message) {
    final store = _storage;
    if (store == null) return;
    final now = DateTime.now();
    final line =
        '${now.toIso8601String()} +${_clock.elapsedMilliseconds}ms '
        '[$tag] $message\n';
    try {
      if (_open.isEmpty || tag == 'erro') store.append('app', line);
      if (_open.isNotEmpty) store.append(_open.last.key, line);
    } catch (_) {
      // Log nunca pode derrubar o app.
    }
  }

  /// Abre uma sessão. As linhas seguintes vão para ela até [endSession] (ou
  /// até abrir outra por cima, como o exercício dentro da aula).
  static DiagSession? beginSession(String kind, String name) {
    final store = _storage;
    if (store == null) return null;
    final s = DiagSession._(
      's${(++_seq).toString().padLeft(5, '0')}',
      kind,
      name,
      DateTime.now(),
    );
    _open.add(s);
    store.append(
      s.key,
      '#sessao tipo=$kind nome=${jsonEncode(name)} '
      'inicio=${s.start.toIso8601String()}\n',
    );
    log('sessao', 'início: $kind $name');
    return s;
  }

  /// Fecha a sessão (pode ser a de baixo da pilha). Passa a valer a regra
  /// das [keepEnded] últimas.
  static void endSession(DiagSession? s) {
    if (s == null || !_open.remove(s)) return;
    // O fim vai para a própria sessão, mesmo que outra esteja por cima.
    _storage?.append(
      s.key,
      '${DateTime.now().toIso8601String()} +${_clock.elapsedMilliseconds}ms '
      '[sessao] fim: ${s.kind} ${s.name}\n',
    );
    _ended.add(s.key);
    _trim();
  }

  static void _trim() {
    while (_ended.length > keepEnded) {
      _storage?.remove(_ended.removeAt(0));
    }
  }

  /// Registra o que a tela sabe do momento (página, posição, notas…) sob
  /// [key]: [provider] devolve algo que o `jsonEncode` entenda. Vai no
  /// relatório e em [logState]. Devolve quem desfaz o registro (chamar no
  /// `dispose`); registrar a mesma chave de novo substitui a anterior.
  static VoidCallback setState(String key, Object? Function() provider) {
    _providers[key] = provider;
    return () {
      if (identical(_providers[key], provider)) _providers.remove(key);
    };
  }

  /// O que cada [setState] diz agora.
  static Map<String, Object?> snapshot() {
    final out = <String, Object?>{};
    for (final e in _providers.entries) {
      try {
        out[e.key] = e.value();
      } catch (err) {
        out[e.key] = 'erro ao ler o estado: $err';
      }
    }
    return out;
  }

  /// Grava o [snapshot] no log, com [why] dizendo o motivo.
  static void logState(String why) {
    if (_storage == null || _providers.isEmpty) return;
    log('estado', '$why ${jsonEncode(snapshot(), toEncodable: _encode)}');
  }

  static Object? _encode(Object? o) => o.toString();

  /// O [snapshot] em JSON legível.
  static String snapshotJson() =>
      const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(jsonEncode(snapshot(), toEncodable: _encode)));

  /// Registra um texto grande que só o relatório leva, num arquivo próprio
  /// (`anexos/<name>`): o MusicXML do exercício, por exemplo. Registrar o
  /// mesmo nome de novo substitui. Devolve quem desfaz o registro.
  static VoidCallback setAttachment(String name, String Function() provider) {
    _attachments[name] = provider;
    return () {
      if (identical(_attachments[name], provider)) _attachments.remove(name);
    };
  }

  /// O texto de cada [setAttachment], pelo nome.
  static Map<String, String> attachments() {
    final out = <String, String>{};
    for (final e in _attachments.entries) {
      try {
        out[e.key] = e.value();
      } catch (err) {
        out[e.key] = 'erro ao ler o anexo: $err';
      }
    }
    return out;
  }

  /// Registra o que parar quando o aluno aperta "Reportar bug" (o áudio e o
  /// metrônomo; as animações a tela do relatório congela por conta própria).
  /// Devolve quem desfaz o registro.
  static VoidCallback addFreezeHook(VoidCallback hook) {
    _freezeHooks.add(hook);
    return () => _freezeHooks.remove(hook);
  }

  /// Chama os ganchos de [addFreezeHook].
  static void freeze() {
    log('app', 'congelado para o relatório de bug');
    logState('ao congelar');
    for (final h in List.of(_freezeHooks)) {
      try {
        h();
      } catch (e) {
        log('erro', 'gancho de congelar: $e');
      }
    }
  }

  /// Os arquivos do log para o relatório: `app` e as sessões guardadas, da
  /// mais antiga para a mais nova.
  static List<DiagLogFile> collect() {
    final store = _storage;
    if (store == null) return const [];
    final keys = <String>[..._ended, for (final s in _open) s.key]..sort();
    return [
      if (store.keys().contains('app'))
        DiagLogFile('app.log', store.read('app')),
      for (final k in keys) DiagLogFile('$k.log', store.read(k)),
    ];
  }
}
