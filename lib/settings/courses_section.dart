import 'dart:async';

import 'package:flutter/material.dart';

import '../course/course_store.dart';
import '../ui/theme.dart';

/// A seção **Cursos** das configurações gerais (I04): os instalados, instalar
/// outro e remover. O embutido não aparece (não pode sair). Fala com o
/// [CourseStore]; quem instala é [onInstall] (o fluxo do I04, que precisa de
/// uma tela por baixo para os diálogos). Modelo: `LibrariesSection`.
class CoursesSection extends StatelessWidget {
  const CoursesSection({
    super.key,
    required this.store,
    required this.onInstall,
  });

  final CourseStore store;
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
              'Cursos',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          if (store.installed.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'Nenhum curso instalado. O curso inicial não aparece aqui.',
                style: TextStyle(fontSize: 13, color: kInkCaption),
              ),
            ),
          for (final course in store.installed)
            _CourseRow(
              course: course,
              onRemove: () => unawaited(_remove(context, course)),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.add, size: 20),
            title: const Text('Instalar outro…'),
            subtitle: const Text('abre um arquivo .zywny'),
            onTap: onInstall,
          ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, InstalledCourse course) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remover ${course.title}?'),
        content: const Text(
          'O curso sai do aparelho. Seu progresso fica guardado: se você '
          'reinstalá-lo, tudo volta.',
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
      await store.remove(course.id);
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não consegui remover ${course.title}: $e')),
      );
    }
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course, required this.onRemove});

  final InstalledCourse course;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.school_outlined, size: 20),
      title: Text(course.title),
      subtitle: Text('versão ${course.version} · por ${course.author}'),
      trailing: IconButton(
        tooltip: 'Remover ${course.title}',
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: onRemove,
      ),
    );
  }
}
