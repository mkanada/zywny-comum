import 'dart:async';

import 'package:flutter/material.dart';

import '../library/library_store.dart';
import '../ui/theme.dart';

/// A seção **Bibliotecas** das configurações gerais (B06): as instaladas, a
/// em uso marcada, trocar de uma para outra, instalar outra, remover e ver os
/// créditos. Fala com o [LibraryStore]; quem instala é [onInstall] (o fluxo
/// do B05, que precisa de uma tela por baixo para os diálogos).
class LibrariesSection extends StatelessWidget {
  const LibrariesSection({
    super.key,
    required this.store,
    required this.onInstall,
  });

  final LibraryStore store;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Text(
              'Bibliotecas',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          if (store.installed.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'Nenhuma biblioteca instalada.',
                style: TextStyle(fontSize: 13, color: kInkCaption),
              ),
            ),
          for (final library in store.installed)
            _LibraryRow(
              library: library,
              active: library.id == store.activeId,
              onUse: () => unawaited(store.setActive(library.id)),
              onAbout: () => _about(context, library),
              onRemove: () => unawaited(_remove(context, library)),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.add, size: 20),
            title: const Text('Instalar outra…'),
            subtitle: const Text('abre um arquivo .zywny'),
            onTap: onInstall,
          ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, InstalledLibrary library) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remover ${library.name}?'),
        content: Text(
          'As partituras saem do aparelho. Seu progresso e seus ajustes '
          'ficam guardados: se você instalar ${library.name} de novo, '
          'tudo volta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await store.remove(library.id);
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não consegui remover ${library.name}: $e')),
      );
    }
  }

  void _about(BuildContext context, InstalledLibrary library) {
    final credits = library.credits?.trim();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(library.name),
          content: SingleChildScrollView(
            child: Text(
              'Versão ${library.version}\n'
              '${library.pieceCount} ${library.term.plural}\n\n'
              '${credits == null || credits.isEmpty ? 'Sem créditos no pacote.' : credits}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Action { about, remove }

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.library,
    required this.active,
    required this.onUse,
    required this.onAbout,
    required this.onRemove,
  });

  final InstalledLibrary library;
  final bool active;
  final VoidCallback onUse;
  final VoidCallback onAbout;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: active,
      selectedColor: kAccent,
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 20,
        semanticLabel: active ? 'em uso' : null,
      ),
      title: Text(library.name),
      subtitle: Text(
        '${active ? 'em uso · ' : ''}versão ${library.version} · '
        '${library.pieceCount} ${library.term.plural}',
      ),
      onTap: active ? null : onUse,
      trailing: PopupMenuButton<_Action>(
        tooltip: 'Mais sobre ${library.name}',
        onSelected: (a) => switch (a) {
          _Action.about => onAbout(),
          _Action.remove => onRemove(),
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _Action.about,
            child: Text('Sobre esta biblioteca'),
          ),
          PopupMenuItem(value: _Action.remove, child: Text('Remover…')),
        ],
      ),
    );
  }
}
