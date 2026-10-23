import 'package:flutter/widgets.dart';
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

/// Declara que esta tela está aberta, com um nome que o relatório entenda
/// ("curso 3", "treino de leitura").
class DiagScreen extends StatefulWidget {
  const DiagScreen({super.key, required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  State<DiagScreen> createState() => _DiagScreenState();
}

class _DiagScreenState extends State<DiagScreen> {
  late String _name;

  @override
  void initState() {
    super.initState();
    _open(widget.name);
  }

  void _open(String name) {
    _name = name;
    DiagScreens._screens.add(name);
    DiagLog.log('nav', 'tela aberta: $name');
  }

  void _close() {
    DiagScreens._screens.remove(_name);
    DiagLog.log('nav', 'tela fechada: $_name');
  }

  @override
  void didUpdateWidget(DiagScreen old) {
    super.didUpdateWidget(old);
    if (widget.name != _name) {
      _close();
      _open(widget.name);
    }
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Uma tela de exercício, música ou aula: abre uma **sessão** do log
/// ([DiagLog.beginSession]) enquanto estiver aberta — o log rotativo guarda
/// as últimas — e se declara como [DiagScreen].
///
/// Trocar [name] (o próximo passo na mesma tela) encerra a sessão e abre
/// outra.
class DiagSessionScope extends StatefulWidget {
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
  State<DiagSessionScope> createState() => _DiagSessionScopeState();
}

class _DiagSessionScopeState extends State<DiagSessionScope> {
  DiagSession? _session;

  @override
  void initState() {
    super.initState();
    _session = DiagLog.beginSession(widget.kind, widget.name);
  }

  @override
  void didUpdateWidget(DiagSessionScope old) {
    super.didUpdateWidget(old);
    if (widget.name != old.name || widget.kind != old.kind) {
      DiagLog.endSession(_session);
      _session = DiagLog.beginSession(widget.kind, widget.name);
    }
  }

  @override
  void dispose() {
    DiagLog.endSession(_session);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      DiagScreen(name: '${widget.kind} ${widget.name}', child: widget.child);
}
