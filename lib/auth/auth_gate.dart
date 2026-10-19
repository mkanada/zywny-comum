import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zywny_auth/zywny_auth.dart';

import '../ui/brand.dart';
import '../ui/theme.dart';
import 'sign_in_screen.dart';

/// O portão da autenticação (D02): o que decide se o app abre.
///
/// Sem conta, o app mostra só a tela de entrada (D-NEG-SEM-CONTA). Com a
/// sessão guardada vencida (7 dias sem rede — D-NEG-OFFLINE), o app pede
/// conexão antes de abrir. Com a conta, o [child] aparece.
///
/// Sem [store] (os testes dos apps, que não têm rede nem Firebase), o portão
/// não segura nada: o [child] aparece logo.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.store,
    required this.child,
    this.requireNickname = false,
  });

  /// Quem guarda a sessão (D01); `null` deixa o app passar direto.
  final AuthStore? store;

  /// O app, quando a conta está em ordem.
  final Widget child;

  /// Perguntar o apelido no primeiro acesso (D-NEG-PRIVACIDADE): só quando
  /// o pedido é ligado — do jeito que está, os testes (com o
  /// [FakeAuthStore]) entram no app sem responder nada.
  final bool requireNickname;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    final store = widget.store;
    if (store != null) unawaited(_restore(store));
  }

  /// Lê a sessão guardada no aparelho. Enquanto isso roda, o estado é
  /// `initializing` e a tela mostra o carregando.
  Future<void> _restore(AuthStore store) async {
    try {
      await store.restore();
    } on Object {
      // A sessão guardada não pôde ser lida: o store fica como está, e o app
      // mostra o que ele disser (a tela de entrada, em geral).
    }
  }

  @override
  void didUpdateWidget(AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // O store mudou: a sessão guardada é lida de novo.
    if (oldWidget.store != widget.store && widget.store != null) {
      unawaited(_restore(widget.store!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (store == null) return widget.child;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => _view(store),
    );
  }

  Widget _view(AuthStore store) {
    final state = store.value;
    return switch (state.status) {
      AuthStatus.initializing => const _AuthLoading(),
      AuthStatus.unauthenticated => SignInScreen(store: store),
      AuthStatus.offlineExpired => _ReconnectScreen(
        store: store,
        message:
            state.errorMessage ??
            'Faz mais de 7 dias sem conexão. Conecte-se à internet para '
                'renovar seu acesso.',
      ),
      AuthStatus.authenticated => _authenticated(store, state),
    };
  }

  /// Com a conta em ordem, o app abre — ou a pergunta do apelido, quando o
  /// pedido está ligado e o apelido ainda não foi escolhido.
  Widget _authenticated(AuthStore store, AuthState state) {
    final user = state.user;
    if (widget.requireNickname &&
        user != null &&
        (user.nickname ?? '').trim().isEmpty) {
      return _NicknameStep(store: store, user: user);
    }
    return widget.child;
  }
}

/// O carregando: o app ainda não sabe se há sessão guardada.
class _AuthLoading extends StatelessWidget {
  const _AuthLoading();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: kLibraryBg,
    child: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMonogram(),
            SizedBox(height: 18),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A sessão guardada passou dos 7 dias sem rede (D-NEG-OFFLINE): o app pede
/// conexão, com a opção de trocar de conta.
class _ReconnectScreen extends StatefulWidget {
  const _ReconnectScreen({required this.store, required this.message});

  final AuthStore store;
  final String message;

  @override
  State<_ReconnectScreen> createState() => _ReconnectScreenState();
}

class _ReconnectScreenState extends State<_ReconnectScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.refreshSession();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = 'Não consegui falar com o servidor: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchAccount() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.signOut();
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Não consegui sair da conta: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AuthPanel(
      children: [
        const Center(child: BrandMonogram()),
        const SizedBox(height: 18),
        Text(
          'Conexão necessária',
          textAlign: TextAlign.center,
          style: serifDisplay(fontSize: 26),
        ),
        const SizedBox(height: 8),
        Text(
          widget.message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: kInkCaption),
        ),
        const SizedBox(height: 22),
        if (error != null) ...[
          AuthMessage(text: error),
          const SizedBox(height: 14),
        ],
        FilledButton(
          onPressed: _busy ? null : _retry,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Tentar novamente'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _switchAccount,
          child: const Text('Trocar de conta'),
        ),
      ],
    );
  }
}

/// O primeiro acesso: o apelido (D-NEG-PRIVACIDADE) e o aceite da política
/// de privacidade — com o aviso para quem tem menos de 12 anos (o aceite do
/// responsável é dado no formulário da plataforma).
class _NicknameStep extends StatefulWidget {
  const _NicknameStep({required this.store, required this.user});

  final AuthStore store;
  final AuthUser user;

  @override
  State<_NicknameStep> createState() => _NicknameStepState();
}

class _NicknameStepState extends State<_NicknameStep> {
  final _controller = TextEditingController();
  bool _accepted = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _controller.text.trim().isNotEmpty && _accepted && !_busy;

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.updateNickname(_controller.text);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Não consegui guardar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AuthPanel(
      children: [
        const Center(child: BrandMonogram()),
        const SizedBox(height: 18),
        Text(
          'Como você quer ser chamado?',
          textAlign: TextAlign.center,
          style: serifDisplay(fontSize: 24),
        ),
        const SizedBox(height: 8),
        Text(
          'O Zywny te chama pelo apelido. Ele fica só no seu aparelho, e é o '
          'que o seu tutor vê.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: kInkCaption),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _controller,
          autofocus: false,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_canContinue) unawaited(_continue());
          },
          decoration: const InputDecoration(
            labelText: 'Apelido',
            hintText: 'Como te chamamos?',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _accepted,
          onChanged: (v) => setState(() => _accepted = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Li a política de privacidade e aceito o uso dos meus dados de '
            'estudo (o tutor vê o que eu pratico).',
            style: TextStyle(fontSize: 13, height: 1.35),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Menor de 12 anos? O aceite do responsável é dado no formulário da '
          'plataforma.',
          style: TextStyle(fontSize: 12, color: kInkCaption, height: 1.35),
        ),
        const SizedBox(height: 18),
        if (error != null) ...[
          AuthMessage(text: error),
          const SizedBox(height: 14),
        ],
        FilledButton(
          onPressed: _canContinue ? _continue : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}
