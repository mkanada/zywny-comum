import 'package:flutter/material.dart';
import 'package:zywny_auth/zywny_auth.dart';

import '../ui/brand.dart';
import '../ui/theme.dart';

/// O cartão que segura as telas de entrada (a de entrada propriamente dita,
/// a de reconexão e a do apelido). As três são a mesma coisa com textos
/// diferentes: o fundo claro da biblioteca, um cartão mais claro no meio e o
/// monograma da marca no alto.
class AuthPanel extends StatelessWidget {
  const AuthPanel({super.key, required this.children, this.scrollable = true});

  final List<Widget> children;

  /// Em tela baixa (celular deitado) o cartão pode ser mais alto que a
  /// janela: ele rola, em vez de estourar.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Material(
        color: kLibraryCardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
    return ColoredBox(
      color: kLibraryBg,
      child: SafeArea(
        child: Center(
          child: scrollable
              ? SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: content,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: content,
                ),
        ),
      ),
    );
  }
}

/// A tela de entrada do Zywny (D02): o login social (D-NEG-AUTH).
///
/// Sem conta conectada o app mostra só esta tela (D-NEG-SEM-CONTA): o
/// [AuthGate] a troca pelo app assim que o estado passa a `authenticated`.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.store,
    this.providers = defaultProviders,
  });

  /// O contrato de autenticação (D01): quem faz o login e guarda a sessão.
  final AuthStore store;

  /// Os provedores oferecidos, na ordem em que aparecem: o primeiro é o
  /// principal (o botão cheio), os outros vêm abaixo.
  final List<SocialProvider> providers;

  /// Google primeiro. Os outros aparecem para quem os tem configurados, mas
  /// nem toda plataforma entra por eles (no computador, só o Google — D01).
  static const defaultProviders = <SocialProvider>[
    SocialProvider.google,
    SocialProvider.apple,
    SocialProvider.microsoft,
    SocialProvider.github,
  ];

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  /// O provedor cujo login está em curso (o botão dele mostra o carregando).
  SocialProvider? _busy;

  /// O erro que o store lançou (quando ele guarda a mensagem no estado, é a
  /// de lá que vale).
  String? _error;

  Future<void> _signIn(SocialProvider provider) async {
    setState(() {
      _busy = provider;
      _error = null;
    });
    try {
      await widget.store.signInWithProvider(provider);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Não consegui entrar: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final message = _error ?? widget.store.value.errorMessage;
        return AuthPanel(
          children: [
            const Center(child: BrandMonogram()),
            const SizedBox(height: 18),
            Text(
              'Entrar no Zywny',
              textAlign: TextAlign.center,
              style: serifDisplay(fontSize: 26),
            ),
            const SizedBox(height: 8),
            Text(
              'Entre com sua conta para guardar seu progresso e ver o que o '
              'seu tutor preparou para você.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: kInkCaption),
            ),
            const SizedBox(height: 22),
            if (message != null) ...[
              AuthMessage(text: message),
              const SizedBox(height: 14),
            ],
            for (final (i, provider) in widget.providers.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                child: _ProviderButton(
                  provider: provider,
                  primary: i == 0,
                  busy: _busy == provider,
                  onTap: () => _signIn(provider),
                ),
              ),
            const SizedBox(height: 18),
            Text(
              'Ao entrar você aceita a política de privacidade do Zywny.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: kInkMuted),
            ),
          ],
        );
      },
    );
  }
}

/// O aviso da tela (o login recusado, a sessão vencida): a mensagem que o
/// store deu, em português.
class AuthMessage extends StatelessWidget {
  const AuthMessage({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: kBadColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kBadColor.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 18, color: kBadColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: kInk, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

/// O botão de um provedor. O principal (o primeiro) é cheio; os outros são
/// delineados, menores.
class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.provider,
    required this.primary,
    required this.busy,
    required this.onTap,
  });

  final SocialProvider provider;

  /// O botão principal da tela.
  final bool primary;

  /// O login deste provedor está em curso.
  final bool busy;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = Text('Entrar com ${provider.label}');
    final icon = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : _ProviderIcon(provider: provider);
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        const SizedBox(width: 10),
        Flexible(child: label),
      ],
    );
    if (!primary) {
      return OutlinedButton(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          foregroundColor: kInk,
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        // O botão do Google é branco, com a borda da biblioteca: é o que a
        // tela do Google usa.
        backgroundColor: kSurface,
        foregroundColor: kInk,
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: kBorder),
      ),
      child: child,
    );
  }
}

/// A marca do provedor no botão: o "G" do Google dentro de um círculo
/// branco; nos outros, o ícone do Material.
class _ProviderIcon extends StatelessWidget {
  const _ProviderIcon({required this.provider});

  final SocialProvider provider;

  @override
  Widget build(BuildContext context) {
    if (provider == SocialProvider.google) {
      return Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: const Text(
          'G',
          style: TextStyle(
            fontSize: 13,
            height: 1,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4285F4),
          ),
        ),
      );
    }
    return Icon(_iconFor(provider), size: 20, color: kInkCaption);
  }

  static IconData _iconFor(SocialProvider provider) => switch (provider) {
    SocialProvider.google => Icons.g_mobiledata,
    SocialProvider.apple => Icons.apple,
    SocialProvider.microsoft => Icons.window,
    SocialProvider.github => Icons.code,
    SocialProvider.facebook => Icons.facebook,
  };
}
