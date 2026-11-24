import 'package:flutter/widgets.dart';
import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_diag/diag_log.dart';

/// Quem sabe em que tela o aluno está: as telas que se declaram com
/// [DiagScreen] e [DiagSession] (na ordem em que abriram) e o `Navigator`,
/// por [observer].
///
/// Os nomes são declarados porque `runtimeType` sai ofuscado na Web.
class DiagScreens {
  DiagScreens._();

  static final List<String> _screens = [];
  static final List<String> _routes = [];

  /// O observador do `Navigator`: `MaterialApp(navigatorObservers: [...])`.
  static final NavigatorObserver observer = _RouteLogger();

  /// As telas abertas, da primeira à de cima.
  static List<String> get screens => List.unmodifiable(_screens);

  /// As rotas do `Navigator`, da primeira à de cima.
  static List<String> get routes => List.unmodifiable(_routes);

  /// Registra a tela no estado do relatório (`telas`, `rotas`). Chamado uma
  /// vez, onde o app liga o log.
  static void registerState() {
    DiagLog.setState('telas', () => {'telas': screens, 'rotas': routes});
  }
}

class _RouteLogger extends NavigatorObserver {
  String _label(Route<dynamic>? r) =>
      r == null ? '-' : (r.settings.name ?? r.runtimeType.toString());

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    DiagScreens._routes.add(_label(route));
    DiagLog.log(
      'nav',
      'push ${_label(route)} (sobre ${_label(previousRoute)})',
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    DiagScreens._routes.remove(_label(route));
    DiagLog.log(
      'nav',
      'pop ${_label(route)} (volta a ${_label(previousRoute)})',
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    DiagScreens._routes.remove(_label(route));
    DiagLog.log('nav', 'remove ${_label(route)}');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    DiagScreens._routes.remove(_label(oldRoute));
    if (newRoute != null) DiagScreens._routes.add(_label(newRoute));
    DiagLog.log('nav', 'replace ${_label(oldRoute)} por ${_label(newRoute)}');
  }
}

void _abrirTela(String name) {
  DiagScreens._screens.add(name);
  DiagLog.log('nav', 'tela aberta: $name');
}

void _fecharTela(String name) {
  DiagScreens._screens.remove(name);
  DiagLog.log('nav', 'tela fechada: $name');
}

/// O nome da tela que está declarada aberta.
class DiagScreenState extends Equatable {
  const DiagScreenState({required this.name});

  final String name;

  @override
  List<Object?> get props => [name];
}

/// Declara a tela aberta: abre no construtor e fecha no close(). Trocar o
/// nome (outro passo na mesma tela) fecha o antigo e abre o novo.
class DiagScreenCubit extends Cubit<DiagScreenState> {
  DiagScreenCubit({required String name}) : super(DiagScreenState(name: name)) {
    _abrirTela(name);
  }

  /// Troca o nome da tela. Sem mudança, não faz nada.
  void trocar(String name) {
    if (name == state.name) return;
    _fecharTela(state.name);
    _abrirTela(name);
    emit(DiagScreenState(name: name));
  }

  @override
  Future<void> close() {
    _fecharTela(state.name);
    return super.close();
  }
}

/// Declara que esta tela está aberta, com um nome que o relatório entenda
/// ("curso 3", "treino de leitura").
class DiagScreen extends StatelessWidget {
  const DiagScreen({super.key, required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => DiagScreenCubit(name: name),
    lazy: false,
    child: Builder(
      builder: (context) {
        // Roda a cada build da tela de cima. Sem mudança de nome, não faz
        // nada; com nome novo, troca antes de a tela de dentro ser montada.
        context.read<DiagScreenCubit>().trocar(name);
        return child;
      },
    ),
  );
}

/// O tipo e o nome da sessão aberta de uma tela.
class DiagSessionState extends Equatable {
  const DiagSessionState({required this.kind, required this.name});

  final String kind;
  final String name;

  @override
  List<Object?> get props => [kind, name];
}

/// Abre a sessão do log ([DiagLog.beginSession]) no construtor e a fecha no
/// close(). Trocar o tipo ou o nome encerra a sessão e abre outra.
class DiagSessionCubit extends Cubit<DiagSessionState> {
  DiagSessionCubit({required String kind, required String name})
    : _session = DiagLog.beginSession(kind, name),
      super(DiagSessionState(kind: kind, name: name));

  DiagSession? _session;

  /// Troca a sessão se o tipo ou o nome mudou. Sem mudança, não faz nada.
  void trocar({required String kind, required String name}) {
    if (kind == state.kind && name == state.name) return;
    DiagLog.endSession(_session);
    _session = DiagLog.beginSession(kind, name);
    emit(DiagSessionState(kind: kind, name: name));
  }

  @override
  Future<void> close() {
    DiagLog.endSession(_session);
    return super.close();
  }
}

/// Uma tela de exercício, música ou aula: abre uma **sessão** do log
/// ([DiagLog.beginSession]) enquanto estiver aberta — o log rotativo guarda
/// as últimas — e se declara como [DiagScreen].
///
/// Trocar [name] (o próximo passo na mesma tela) encerra a sessão e abre
/// outra.
class DiagSessionScope extends StatelessWidget {
  const DiagSessionScope({
    super.key,
    required this.kind,
    required this.name,
    required this.child,
  });

  /// `exercicio`, `musica`, `aula`…
  final String kind;
  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => DiagSessionCubit(kind: kind, name: name),
    lazy: false,
    child: Builder(
      builder: (context) {
        // Ver DiagScreen: a troca acontece aqui, antes da tela de dentro.
        context.read<DiagSessionCubit>().trocar(kind: kind, name: name);
        return DiagScreen(name: '$kind $name', child: child);
      },
    ),
  );
}
