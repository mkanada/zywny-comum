import 'dart:async';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'library_package.dart';
import 'library_store.dart';

/// Abre o seletor de arquivos para um `.zywny` e devolve os bytes; `null` se
/// o usuário cancelou. No Android o filtro por extensão vira filtro por MIME,
/// e `.zywny` não tem MIME conhecido (o arquivo nem apareceria): lá não se
/// filtra e a validação do pacote é quem recusa o que não serve.
Future<Uint8List?> pickLibraryBytes() async {
  final file = await openFile(
    acceptedTypeGroups: [
      !kIsWeb && Platform.isAndroid
          ? const XTypeGroup(label: 'biblioteca')
          : const XTypeGroup(label: 'biblioteca', extensions: ['zywny']),
    ],
  );
  return file?.readAsBytes();
}

/// Escolher → validar → (perguntar, se o `id` já está instalado) → gravar →
/// virar a em uso → avisar. Devolve a biblioteca instalada, ou `null` se o
/// usuário cancelou ou deu erro (que o diálogo já explicou); nesse caso nada
/// foi gravado. Usado pela tela vazia (B05) e pelas configurações (B06).
Future<InstalledLibrary?> installLibraryFromFile(
  BuildContext context,
  LibraryStore store, {
  Future<Uint8List?> Function() pick = pickLibraryBytes,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  Future<T> whileBusy<T>(String message, Future<T> Function() work) async {
    unawaited(
      showDialog<void>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (_) => _BusyDialog(message),
      ),
    );
    try {
      return await work();
    } finally {
      navigator.pop();
    }
  }

  Future<void> showError(String message) => showDialog<void>(
    context: navigator.context,
    builder: (context) => AlertDialog(
      title: const Text('Não deu para instalar'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  try {
    final Uint8List? bytes;
    try {
      bytes = await pick();
    } on Object catch (e) {
      await showError('Não consegui abrir o seletor de arquivos: $e');
      return null;
    }
    if (bytes == null) return null;

    final LibraryPackage package;
    try {
      package = await whileBusy(
        'Lendo a biblioteca…',
        () => store.inspect(bytes!),
      );
    } on LibraryFormatException catch (e) {
      await showError(e.message);
      return null;
    }

    final installed = store[package.manifest.id];
    if (installed != null) {
      if (!navigator.mounted) return null;
      final replace = await showDialog<bool>(
        context: navigator.context,
        builder: (context) =>
            _ReplaceDialog(installed: installed, incoming: package),
      );
      if (replace != true) return null;
    }

    final InstalledLibrary library;
    try {
      library = await whileBusy(
        'Instalando…',
        () => store.install(bytes!, inspected: package),
      );
    } on Object catch (e) {
      await showError(
        e is LibraryFormatException
            ? e.message
            : 'Não consegui guardar a biblioteca: $e',
      );
      return null;
    }
    final count = library.pieceCount;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${library.name} instalada ($count '
          '${count == 1 ? library.term.singular : library.term.plural})',
        ),
      ),
    );
    return library;
  } on Object {
    // A tela saiu do ar no meio (o diálogo já tinha sido fechado).
    return null;
  }
}

class _BusyDialog extends StatelessWidget {
  const _BusyDialog(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

/// D-BIB-ATUALIZAR: mostra as duas versões, também quando a nova é mais
/// antiga — o app não decide qual vale mais.
class _ReplaceDialog extends StatelessWidget {
  const _ReplaceDialog({required this.installed, required this.incoming});

  final InstalledLibrary installed;
  final LibraryPackage incoming;

  @override
  Widget build(BuildContext context) {
    final m = incoming.manifest;
    return AlertDialog(
      title: Text('Substituir ${installed.name}?'),
      content: Text(
        'Instalada: versão ${installed.version} '
        '(${installed.pieceCount} ${installed.term.plural}).\n'
        'Do arquivo: versão ${m.version} '
        '(${incoming.pieces.length} ${m.term.plural}).\n\n'
        'Seu progresso e seus ajustes ficam.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Substituir'),
        ),
      ],
    );
  }
}
