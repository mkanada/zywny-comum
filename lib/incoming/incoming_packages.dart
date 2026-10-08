// B11 — arquivos `.zywny` que o sistema entrega ao app: clique duplo no
// gerenciador de arquivos, "Abrir com…", um download tocado na notificação.
//
// Este arquivo só recebe e guarda. Quem instala é a tela da biblioteca, pelo
// mesmo fluxo do "Abrir arquivo…" (`installPackageFromFile`): o app não
// distingue de onde veio o pacote.
//
// Como o arquivo chega em cada plataforma:
// - Android: a `MainActivity` copia o conteúdo do intent para o cache e avisa
//   por um canal (`zywny/incoming`).
// - Linux: o caminho vem em `main(args)` na primeira abertura; com o app já
//   aberto, o `my_application.cc` repassa o caminho pelo mesmo canal.
// - Windows (quando houver, fase X02): o caminho vem em `main(args)`.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Um `.zywny` que o sistema entregou. Os bytes só são lidos quando alguém
/// pede ([read]): o pacote dos hinos passa de alguns MB e pode esperar a
/// tela estar pronta.
class IncomingPackage {
  const IncomingPackage({required this.name, required this.read});

  /// Nome do arquivo, para as mensagens ("Não consegui ler hinos.zywny").
  final String name;

  /// Lê o conteúdo; lança se o arquivo sumiu ou o sistema negou o acesso.
  final Future<Uint8List> Function() read;
}

/// A fila entre o sistema e a tela da biblioteca.
///
/// O arquivo que abre o app chega **antes** de a tela existir: fica guardado
/// até alguém ligar-se com [attach], que recebe tudo o que esperava. Daí em
/// diante cada arquivo novo vai direto a quem estiver ligado.
class IncomingPackages {
  IncomingPackages();

  final List<IncomingPackage> _waiting = [];
  void Function(IncomingPackage package)? _listener;

  /// Há arquivo esperando por quem se ligue.
  bool get hasWaiting => _waiting.isNotEmpty;

  /// Entrega [package] a quem está ligado, ou guarda até alguém se ligar.
  void add(IncomingPackage package) {
    final listener = _listener;
    if (listener == null) {
      _waiting.add(package);
    } else {
      listener(package);
    }
  }

  /// Liga [listener] e entrega, na hora, o que esperava. Um só de cada vez.
  void attach(void Function(IncomingPackage package) listener) {
    _listener = listener;
    final waiting = List.of(_waiting);
    _waiting.clear();
    waiting.forEach(listener);
  }

  /// Desliga [listener] (a tela saiu do ar); o que vier depois volta a esperar.
  void detach(void Function(IncomingPackage package) listener) {
    if (_listener == listener) _listener = null;
  }
}

/// O canal com o código nativo (Android, Linux).
const String kIncomingChannelName = 'zywny/incoming';

/// Extensão dos pacotes.
const String kPackageExtension = '.zywny';

/// O caminho tem a extensão de um pacote (maiúsculas não importam: o
/// Windows e alguns downloads trocam a caixa).
bool isPackagePath(String path) =>
    path.toLowerCase().endsWith(kPackageExtension);

/// Os caminhos de pacote entre os argumentos da linha de comando. Opções
/// (`--debug`, `--curso <pasta>`) e o que não termina em `.zywny` passam
/// batido; um `file:///…` (o que alguns gerenciadores de arquivos mandam) vira
/// o caminho dele.
List<String> packagePathsIn(List<String> args) => [
  for (final arg in args)
    if (!arg.startsWith('--') && isPackagePath(arg)) _asPath(arg),
];

String _asPath(String arg) {
  if (!arg.toLowerCase().startsWith('file://')) return arg;
  try {
    return Uri.parse(arg).toFilePath();
  } on Object {
    return arg;
  }
}

/// O último trecho do caminho, para mostrar ao usuário.
String baseName(String path) {
  final cut = path.lastIndexOf(RegExp(r'[/\\]'));
  return cut < 0 ? path : path.substring(cut + 1);
}

/// Um pacote lido de um arquivo comum (linha de comando no desktop).
IncomingPackage packageFromPath(String path) =>
    IncomingPackage(name: baseName(path), read: () => File(path).readAsBytes());

/// Um pacote que o código nativo copiou para o cache: depois de lido, a cópia
/// é apagada (ficaria ocupando o cache do aparelho).
IncomingPackage packageFromCache(String name, String path) => IncomingPackage(
  name: name,
  read: () async {
    final file = File(path);
    try {
      return await file.readAsBytes();
    } finally {
      unawaited(file.delete().then<void>((_) {}, onError: (Object _) {}));
    }
  },
);

/// Um pacote que o código nativo não conseguiu entregar (o sistema negou o
/// acesso, o armazenamento encheu…): a leitura lança e a tela explica.
IncomingPackage packageThatFailed(String name, String reason) =>
    IncomingPackage(name: name, read: () => Future.error(reason));

/// Liga [target] ao que o sistema entrega:
/// - [args], os argumentos de `main` (desktop);
/// - o canal nativo (Android; Linux com o app já aberto).
///
/// Sem plugin do outro lado do canal (testes, Web, Windows hoje) a chamada
/// falha em silêncio: é só "ninguém tem nada para entregar".
Future<void> listenForIncomingPackages(
  IncomingPackages target, {
  List<String> args = const [],
  MethodChannel channel = const MethodChannel(kIncomingChannelName),
}) async {
  for (final path in packagePathsIn(args)) {
    target.add(packageFromPath(path));
  }
  if (kIsWeb) return;

  // O Dart se põe à escuta antes de perguntar o que já chegou, para nada cair
  // entre uma coisa e outra.
  channel.setMethodCallHandler((call) async {
    if (call.method == 'file') {
      final package = _fromPayload(call.arguments);
      if (package != null) target.add(package);
    }
    return null;
  });
  try {
    final initial = await channel.invokeListMethod<Object?>('initial');
    for (final payload in initial ?? const <Object?>[]) {
      final package = _fromPayload(payload);
      if (package != null) target.add(package);
    }
  } on MissingPluginException {
    // Plataforma sem o lado nativo: só vale o que veio em [args].
  } on PlatformException {
    // O nativo falhou ao listar: não impede o app de abrir.
  }
}

/// Como o código nativo manda um arquivo: `{name, path}`, com
/// `temporary: true` quando o caminho é uma cópia que ele fez no cache (e que
/// o app apaga depois de ler) — nunca apagamos o arquivo do próprio usuário —,
/// ou `{name, error}` quando não conseguiu entregar.
IncomingPackage? _fromPayload(Object? payload) {
  if (payload is! Map) return null;
  final name = payload['name'] as String? ?? 'arquivo';
  final error = payload['error'] as String?;
  if (error != null) return packageThatFailed(name, error);
  final path = payload['path'] as String?;
  if (path == null) return null;
  return payload['temporary'] == true
      ? packageFromCache(name, path)
      : IncomingPackage(name: name, read: () => File(path).readAsBytes());
}
