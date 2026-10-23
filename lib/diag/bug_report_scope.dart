import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:score_bridge/score_bridge.dart' show ScoreTrace;
import 'package:zywny_diag/diag_log.dart';

import '../about/about_screen.dart' show packageVersionText;
import 'bug_report_builder.dart';
import 'bug_report_delivery.dart';
import 'bug_report_page.dart';
import 'diag_screens.dart';

/// Quantos dedos, e por quanto tempo, abrem o relatório de bug.
const int kBugReportFingers = 3;
const Duration kBugReportHold = Duration(milliseconds: 700);

/// O botão e o gesto de **Reportar bug**, em todas as telas dos dois apps.
///
/// Fica no `MaterialApp.builder`, em volta do `Navigator`. Ao ser chamado
/// ([BugReportScope.start]: o botão das configurações, três dedos parados na
/// tela por [kBugReportHold], ou Ctrl+Shift+B), ele:
///
/// 1. para o que toca (os ganchos de [DiagLog.addFreezeHook]: o agendador de
///    áudio e o metrônomo) e congela as animações (`TickerMode`);
/// 2. tira uma captura da tela como estava;
/// 3. abre a tela do relatório por cima ([BugReportPage]): o aluno escreve o
///    que fazia e o que aconteceu;
/// 4. monta um `.zip` com o texto, a captura, o estado, a pilha de telas e o
///    log rotativo ([DiagLog.collect]) e o entrega (compartilhar no Android,
///    baixar na Web). Nada sai sozinho.
class BugReportScope extends StatefulWidget {
  const BugReportScope({
    super.key,
    required this.appName,
    required this.child,
    @visibleForTesting this.deliver = deliverBugReport,
  });

  /// `aprendizado`, `musicas`: vai no nome do arquivo e no relatório.
  final String appName;
  final Widget child;

  /// Entrega o arquivo; os testes trocam por um falso.
  final Future<BugReportDelivery> Function(String fileName, Uint8List bytes)
  deliver;

  /// O escopo do app (há um só). `null` nos testes sem ele.
  static BugReportScopeState? get current => BugReportScopeState._current;

  /// Abre o relatório de bug agora. No-op sem [BugReportScope].
  static Future<void> start() async => current?.start();

  @override
  State<BugReportScope> createState() => BugReportScopeState();
}

class BugReportScopeState extends State<BugReportScope>
    with WidgetsBindingObserver {
  static BugReportScopeState? _current;

  final GlobalKey _boundary = GlobalKey();
  final Set<int> _pointers = {};
  Timer? _hold;
  bool _frozen = false;
  bool _formShown = false;
  Uint8List? _shot;
  Map<String, String> _device = const {};
  String _version = '';

  @override
  void initState() {
    super.initState();
    _current = this;
    DiagLog.setState('app', () => {'app': widget.appName});
    // O rastro da partitura (player e vista) vai para o mesmo log.
    ScoreTrace.sink = DiagLog.log;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _device = _deviceInfo();
      DiagLog.log(
        'app',
        'aparelho: ${_device.entries.map((e) => '${e.key}=${e.value}').join('; ')}',
      );
      unawaited(
        packageVersionText().then((v) {
          _version = v;
          DiagLog.log('app', v);
        }),
      );
    });
  }

  // -------------------------------------------------------------------------
  // O que acontece ao redor da tela (para quem só percebeu que "algo está
  // errado"): tamanho, tema, memória, quadros lentos, toques.
  // -------------------------------------------------------------------------

  Timer? _metricsTimer;

  @override
  void didChangeMetrics() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final view = View.of(context);
      final size = view.physicalSize / view.devicePixelRatio;
      final pad = view.padding;
      final insets = view.viewInsets;
      final r = view.devicePixelRatio;
      DiagLog.log(
        'tela',
        'tamanho ${size.width.toStringAsFixed(0)}x'
            '${size.height.toStringAsFixed(0)} dp @${r.toStringAsFixed(3)}x, '
            'margens (sistema) '
            'e${(pad.left / r).toStringAsFixed(0)} '
            'c${(pad.top / r).toStringAsFixed(0)} '
            'd${(pad.right / r).toStringAsFixed(0)} '
            'b${(pad.bottom / r).toStringAsFixed(0)}, '
            'teclado/barras ${(insets.bottom / r).toStringAsFixed(0)} dp embaixo',
      );
    });
  }

  @override
  void didChangePlatformBrightness() {
    DiagLog.log(
      'tela',
      'tema do sistema: ${WidgetsBinding.instance.platformDispatcher.platformBrightness.name}',
    );
  }

  @override
  void didChangeTextScaleFactor() {
    DiagLog.log(
      'tela',
      'escala do texto: ${WidgetsBinding.instance.platformDispatcher.textScaleFactor}',
    );
  }

  @override
  void didHaveMemoryPressure() {
    DiagLog.log('app', 'o sistema avisou: pouca memória');
  }

  final Stopwatch _slowClock = Stopwatch()..start();
  int _slowSkipped = 0;

  void _onTimings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      final total = t.totalSpan.inMilliseconds;
      if (total < 100) continue;
      // Um quadro lento por vez no máximo a cada meio segundo.
      if (_slowClock.elapsedMilliseconds < 500) {
        _slowSkipped++;
        continue;
      }
      _slowClock.reset();
      final skipped = _slowSkipped;
      _slowSkipped = 0;
      DiagLog.log(
        'quadro',
        'quadro lento: $total ms '
            '(desenhar ${t.buildDuration.inMilliseconds} ms, '
            'rasterizar ${t.rasterDuration.inMilliseconds} ms)'
            '${skipped > 0 ? ', mais $skipped lentos antes' : ''}',
      );
    }
  }

  final Map<int, _Touch> _touches = {};

  void _touchDown(PointerDownEvent e) {
    _touches[e.pointer] = _Touch(e.position, e.timeStamp, e.kind);
  }

  void _touchMove(PointerMoveEvent e) {
    final t = _touches[e.pointer];
    if (t == null) return;
    final d = (e.position - t.start).distance;
    if (d > t.maxDistance) t.maxDistance = d;
  }

  void _touchEnd(PointerEvent e) {
    final t = _touches.remove(e.pointer);
    if (t == null) return;
    final ms = (e.timeStamp - t.start0).inMilliseconds;
    final screen = DiagScreens.screens.isEmpty ? '-' : DiagScreens.screens.last;
    final fingers = _touches.length + 1;
    final kind = switch (t.kind) {
      ui.PointerDeviceKind.touch => 'dedo',
      ui.PointerDeviceKind.mouse => 'mouse',
      ui.PointerDeviceKind.stylus => 'caneta',
      _ => t.kind.name,
    };
    final what = e is PointerCancelEvent
        ? 'toque cancelado'
        : t.maxDistance > 24
        ? 'arrasto de ${t.maxDistance.toStringAsFixed(0)} px'
        : ms > 500
        ? 'toque longo'
        : 'toque';
    DiagLog.log(
      'toque',
      '$what ($kind) em ${t.start.dx.toStringAsFixed(0)},'
          '${t.start.dy.toStringAsFixed(0)} px, $ms ms, '
          '$fingers ${fingers == 1 ? 'dedo' : 'dedos'} na tela, tela: $screen',
    );
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    if (ScoreTrace.sink == DiagLog.log) ScoreTrace.sink = null;
    _hold?.cancel();
    if (_current == this) _current = null;
    super.dispose();
  }

  /// Congela, captura e abre a tela do relatório.
  Future<void> start() async {
    if (_frozen || !mounted) return;
    DiagLog.log('bug', 'relatório de bug aberto');
    // O que toca para primeiro; a tela congela no mesmo quadro.
    DiagLog.freeze();
    _device = _deviceInfo();
    setState(() => _frozen = true);
    unawaited(packageVersionText().then((v) => _version = v));
    await WidgetsBinding.instance.endOfFrame;
    _shot = await _capture();
    if (!mounted) return;
    setState(() => _formShown = true);
  }

  Map<String, String> _deviceInfo() {
    final mq = MediaQuery.maybeOf(context);
    return {
      'app': 'zywny ${widget.appName}',
      'plataforma':
          '${defaultTargetPlatform.name}${kIsWeb ? ' (web)' : ''}: '
          '${platformDescription()}',
      if (mq != null) ...{
        'tela':
            '${mq.size.width.round()}x${mq.size.height.round()} '
            '@${mq.devicePixelRatio}x, ${mq.orientation.name}',
        'texto': 'escala ${mq.textScaler}',
        'tema': mq.platformBrightness.name,
      },
      'idioma': Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? '-',
    };
  }

  Future<Uint8List?> _capture() async {
    try {
      final boundary =
          _boundary.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ratio = math.min(View.of(context).devicePixelRatio, 2.0);
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } on Object catch (e) {
      DiagLog.log('erro', 'captura de tela para o relatório: $e');
      return null;
    }
  }

  void _cancel() {
    DiagLog.log('bug', 'tela do relatório fechada');
    setState(() {
      _frozen = false;
      _formShown = false;
      _shot = null;
    });
  }

  Future<BugReportDelivery> _submit(String doing, String happened) async {
    final at = DateTime.now();
    DiagLog.log(
      'bug',
      'relatório gerado: fazia="$doing" aconteceu="$happened"',
    );
    final input = BugReportInput(
      appName: widget.appName,
      appVersion: _version.replaceFirst('Versão ', ''),
      at: at,
      doing: doing,
      happened: happened,
      device: _device,
      routes: [
        ...DiagScreens.screens.map((s) => 'tela: $s'),
        ...DiagScreens.routes.map((r) => 'rota: $r'),
      ],
      stateJson: DiagLog.snapshotJson(),
      logs: DiagLog.collect(),
      screenshotPng: _shot,
      attachments: DiagLog.attachments(),
    );
    final name = bugReportFileName(widget.appName, at);
    return widget.deliver(name, buildBugReportZip(input));
  }

  void _pointerDown(PointerDownEvent e) {
    _touchDown(e);
    _pointers.add(e.pointer);
    if (_pointers.length >= kBugReportFingers && !_frozen) {
      _hold?.cancel();
      _hold = Timer(kBugReportHold, () => unawaited(start()));
    }
  }

  void _pointerUp(PointerEvent e) {
    _touchEnd(e);
    _pointers.remove(e.pointer);
    if (_pointers.length < kBugReportFingers) {
      _hold?.cancel();
      _hold = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyB,
          control: true,
          shift: true,
        ): () =>
            unawaited(start()),
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: _pointerDown,
              onPointerMove: _touchMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerUp,
              child: TickerMode(
                enabled: !_frozen,
                child: RepaintBoundary(key: _boundary, child: widget.child),
              ),
            ),
          ),
          if (_formShown)
            Positioned.fill(
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (_) => BugReportPage(
                      screenshot: _shot,
                      onCancel: _cancel,
                      onSubmit: _submit,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Um dedo na tela, do toque ao levantar, para o log.
class _Touch {
  _Touch(this.start, this.start0, this.kind);

  final Offset start;
  final Duration start0;
  final ui.PointerDeviceKind kind;
  double maxDistance = 0;
}
