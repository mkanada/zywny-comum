import 'package:flutter/widgets.dart';

import 'library_package.dart';

/// O termo ("hino", "peça") e a numeração da biblioteca em uso, para os
/// textos fixos lá embaixo na árvore (partitura, trilha, configurações)
/// concordarem sem receber isso por parâmetro. Sem escopo: o hinário.
class LibraryTermScope extends InheritedWidget {
  const LibraryTermScope({
    super.key,
    required this.term,
    this.numbered = true,
    required super.child,
  });

  final LibraryTerm term;
  final bool numbered;

  static LibraryTerm of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LibraryTermScope>()?.term ??
      LibraryTerm.hymn;

  @override
  bool updateShouldNotify(LibraryTermScope old) =>
      old.term != term || old.numbered != numbered;
}
