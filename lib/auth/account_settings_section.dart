import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zywny_auth/zywny_auth.dart';

import '../ui/theme.dart';

/// O código do aluno (D-NEG-VINCULO): o tutor digita este código no painel
/// dele para vincular a conta que a pessoa já tem.
///
/// Sai do `uid` (o identificador da conta no Firebase): oito caracteres em
/// maiúsculas, com um hífen no meio — o bastante para não repetir entre
/// alunos e curto para o tutor digitar.
String studentCodeFor(String uid) {
  final clean = uid.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
  final eight = clean.padRight(8, '0').substring(0, 8);
  return '${eight.substring(0, 4)}-${eight.substring(4)}';
}

/// A seção "Conta" das configurações gerais (D02): quem está conectado, o
/// apelido, o e-mail, o código do aluno, a saída e a exclusão da conta
/// (D-NEG-PRIVACIDADE: a LGPD pede que a pessoa possa apagar os dados).
class AccountSettingsSection extends StatelessWidget {
  const AccountSettingsSection({super.key, required this.store});

  /// A sessão conectada (D01).
  final AuthStore store;

  /// Sai da conta (ou apaga a conta): o app volta para a tela de entrada, e
  /// por isso as telas acima são fechadas.
  Future<void> _finish(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on AuthException catch (e) {
      if (context.mounted) _say(context, e.message);
      return;
    } on Object catch (e) {
      if (context.mounted) _say(context, 'Não consegui: $e');
      return;
    }
    if (!context.mounted) return;
    // Volta para a primeira tela: o [AuthGate] mostra a entrada.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// O apelido: um diálogo com o campo, para trocar quando quiser.
  Future<void> _editNickname(BuildContext context, String? current) async {
    final nickname = await showDialog<String>(
      context: context,
      builder: (context) => _NicknameDialog(current: current),
    );
    if (nickname == null) return;
    try {
      await store.updateNickname(nickname);
    } on AuthException catch (e) {
      if (context.mounted) _say(context, e.message);
    } on Object catch (e) {
      if (context.mounted) _say(context, 'Não consegui guardar: $e');
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar minha conta?'),
        content: const Text(
          'A conta é apagada no servidor e os dados que ficaram neste '
          'aparelho somem. O que você praticou some com ela.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            // A ação que apaga tudo aparece na cor de perigo (R22).
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _finish(context, store.deleteAccount);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final user = store.currentUser;
        if (user == null) return const SizedBox.shrink();
        final code = studentCodeFor(user.uid);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('Conta'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline, size: 20),
              title: const Text('Apelido'),
              subtitle: Text(user.nickname ?? 'ainda não escolhido'),
              trailing: const _RowAction('Alterar'),
              onTap: () => _editNickname(context, user.nickname),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.alternate_email, size: 20),
              title: const Text('E-mail'),
              subtitle: Text(user.email ?? 'a rede social não informou'),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.badge_outlined, size: 20),
              title: const Text('Código do aluno'),
              subtitle: const Text(
                'o tutor digita este código para te vincular',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: kAccent,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar o código',
                    icon: const Icon(Icons.content_copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      _say(context, 'Código copiado: $code');
                    },
                  ),
                ],
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.logout, size: 20),
              title: const Text('Sair da conta'),
              onTap: () => _finish(context, store.signOut),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.delete_forever, size: 20),
              title: const Text('Apagar minha conta e meus dados'),
              subtitle: const Text('a LGPD pede que você possa apagar tudo'),
              onTap: () => _confirmDeleteAccount(context),
            ),
          ],
        );
      },
    );
  }
}

/// O diálogo do apelido: o campo e os dois botões. O campo é do diálogo
/// (e não da seção), para o controlador poder ser descartado junto com ele.
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.current});

  final String? current;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Seu apelido'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Apelido',
        hintText: 'Como te chamamos?',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Salvar'),
      ),
    ],
  );
}

/// O título de uma seção das configurações.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

/// Ação à direita de uma linha das configurações ("Alterar"): inicial
/// maiúscula e cor de destaque, para ler como botão.
class _RowAction extends StatelessWidget {
  const _RowAction(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: kAccent,
    ),
  );
}
