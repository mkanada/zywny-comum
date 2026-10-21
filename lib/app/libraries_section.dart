import 'dart:async';

import 'package:flutter/material.dart';

import 'package:zywny_library/library_store.dart';

import '../ui/theme.dart';

/// A seção **Bibliotecas** das configurações gerais (B06): as instaladas, a
/// em uso marcada, trocar de uma para outra, remover e ver os créditos. Fala
/// com o [LibraryStore]; [onInstall] é o instalador, quando a tela oferece um
/// botão para isso (o zywny-musicas não oferece: o `.zywny` chega pelo
/// "Abrir com…" do sistema).
///
/// A seleção (trocar a em uso) só aparece com mais de uma instalada: com uma
/// só, a linha é só informativa (versão, créditos, remover).
class LibrariesSection extends StatelessWidget {
  const LibrariesSection({
    super.key,
    required this.store,
    this.onInstall,
  });

  final LibraryStore store;

  /// `null` não mostra "Instalar outra…" (a instalação vem de fora do app).
  final VoidCallback? onInstall;

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
              selectable: store.installed.length > 1,
              onUse: () => unawaited(store.setActive(library.id)),
              onAbout: () => _about(context, library),
              onRemove: () => unawaited(_remove(context, library)),
            ),
          if (onInstall case final install?)
            ListTile(
              dense: true,
              leading: const Icon(Icons.add, size: 20),
              title: const Text('Instalar outra…'),
              subtitle: const Text('abre um arquivo .zywny'),
              onTap: install,
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
    required this.selectable,
    required this.onUse,
    required this.onAbout,
    required this.onRemove,
  });

  final InstalledLibrary library;
  final bool active;

  /// Com uma só instalada não há o que trocar: a linha informa (e o menu
  /// mantém "Sobre" e "Remover"), sem o rádio de seleção.
  final bool selectable;
  final VoidCallback onUse;
  final VoidCallback onAbout;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: active,
      selectedColor: kAccent,
      leading: selectable
          ? Icon(
              active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20,
              semanticLabel: active ? 'em uso' : null,
            )
          : const Icon(
              Icons.library_music_outlined,
              size: 20,
              semanticLabel: 'em uso',
            ),
      title: Text(library.name),
      subtitle: Text(
        '${active ? 'em uso · ' : ''}versão ${library.version} · '
        '${library.pieceCount} ${library.term.plural}',
      ),
      onTap: active || !selectable ? null : onUse,
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
