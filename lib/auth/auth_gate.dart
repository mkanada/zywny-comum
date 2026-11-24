import 'package:flutter/material.dart';
import 'package:zywny_auth/zywny_auth.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import '../ui/brand.dart';
import '../ui/theme.dart';
import 'auth_gate_cubit.dart';
import 'nickname_cubit.dart';
import 'reconnect_cubit.dart';
import 'sign_in_screen.dart';

/// O portão da autenticação (D02): o que decide se o app abre.
///
/// Sem conta, o app mostra só a tela de entrada (D-NEG-SEM-CONTA). Com a
/// sessão guardada vencida (7 dias sem rede — D-NEG-OFFLINE), o app pede
/// conexão antes de abrir. Com a conta, o [child] aparece.
///
/// Sem [store] (os testes dos apps, que não têm rede nem Firebase), o portão
/// não segura nada: o [child] aparece logo.
class AuthGate extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final store = this.store;
    if (store == null) return child;
    // A chave é o próprio store: se ele troca, o Cubit é refeito e lê a
    // sessão guardada dele (o `didUpdateWidget` de antes fazia o mesmo).
    return BlocProvider(
      key: ValueKey(store),
      create: (_) => AuthGateCubit(store: store)..restaurar(),
      child: BlocBuilder<AuthGateCubit, AuthState>(
        builder: (context, state) => _view(store, state),
      ),
    );
  }

  Widget _view(AuthStore store, AuthState state) {
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
    if (requireNickname &&
        user != null &&
        (user.nickname ?? '').trim().isEmpty) {
      return _NicknameStep(store: store, user: user);
    }
    return child;
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
class _ReconnectScreen extends StatelessWidget {
  const _ReconnectScreen({required this.store, required this.message});

  final AuthStore store;
  final String message;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ReconnectCubit(store: store),
    child: BlocBuilder<ReconnectCubit, ReconnectState>(
      builder: (context, estado) => _painel(context, estado),
    ),
  );

  Widget _painel(BuildContext context, ReconnectState estado) {
    final cubit = context.read<ReconnectCubit>();
    final error = estado.error;
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
          message,
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
          onPressed: estado.busy ? null : cubit.tentarDeNovo,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: estado.busy
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
          onPressed: estado.busy ? null : cubit.trocarDeConta,
          child: const Text('Trocar de conta'),
        ),
      ],
    );
  }
}

/// O primeiro acesso: o apelido (D-NEG-PRIVACIDADE) e o aceite da política
/// de privacidade — com o aviso para quem tem menos de 12 anos (o aceite do
/// responsável é dado no formulário da plataforma).
class _NicknameStep extends StatelessWidget {
  const _NicknameStep({required this.store, required this.user});

  final AuthStore store;
  final AuthUser user;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => NicknameCubit(store: store),
    child: BlocBuilder<NicknameCubit, NicknameState>(
      builder: (context, estado) => _painel(context, estado),
    ),
  );

  Widget _painel(BuildContext context, NicknameState estado) {
    final cubit = context.read<NicknameCubit>();
    final error = estado.error;
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
        _nicknameField(cubit),
        const SizedBox(height: 12),
        ..._acceptance(cubit, estado),
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
        _continueButton(cubit, estado),
      ],
    );
  }

  /// O campo do apelido: continua pelo teclado, se o apelido vale. Sem
  /// controller: o texto vai para o Cubit a cada tecla.
  Widget _nicknameField(NicknameCubit cubit) => TextField(
    autofocus: false,
    textInputAction: TextInputAction.done,
    onChanged: cubit.editarApelido,
    onSubmitted: (_) => cubit.continuar(),
    decoration: const InputDecoration(
      labelText: 'Apelido',
      hintText: 'Como te chamamos?',
      border: OutlineInputBorder(),
    ),
  );

  /// O aceite da política de privacidade (o uso dos dados de estudo).
  List<Widget> _acceptance(NicknameCubit cubit, NicknameState estado) => [
    CheckboxListTile(
      value: estado.accepted,
      onChanged: (v) => cubit.mudarAceite(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: const Text(
        'Li a política de privacidade e aceito o uso dos meus dados de '
        'estudo (o tutor vê o que eu pratico).',
        style: TextStyle(fontSize: 13, height: 1.35),
      ),
    ),
  ];

  /// O botão de continuar, desligado até o apelido e o aceite estarem prontos.
  Widget _continueButton(NicknameCubit cubit, NicknameState estado) =>
      FilledButton(
        onPressed: estado.podeContinuar ? cubit.continuar : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text('Continuar'),
      );
}
