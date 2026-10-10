import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Em que tipo de aparelho o app roda: muda a orientação da partitura, o
/// tamanho de partida da notação e como os textos chamam o aparelho.
enum DeviceKind {
  /// Android/iOS de tela pequena: a partitura trava deitada (U10).
  phone,

  /// Android/iOS de tela grande: a partitura segue a posição do aparelho,
  /// em pé ou deitada.
  tablet,

  /// Desktop e navegador.
  desktop,
}

/// Lado menor (px lógicos) a partir do qual um Android/iOS é tablet — o
/// corte do Material.
const double kTabletMinShortestSide = 600;

/// O tipo de aparelho para uma janela de [logicalSize]. O lado menor não
/// muda ao girar, então celular e tablet não trocam de tipo no meio do uso.
DeviceKind deviceKindFor(Size logicalSize) {
  final mobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (!mobile) return DeviceKind.desktop;
  return logicalSize.shortestSide >= kTabletMinShortestSide
      ? DeviceKind.tablet
      : DeviceKind.phone;
}

/// [deviceKindFor] da janela deste [context].
DeviceKind deviceKindOf(BuildContext context) =>
    deviceKindFor(MediaQuery.sizeOf(context));

/// [deviceKindFor] da janela do app, para quem ainda não tem contexto com
/// `MediaQuery` (um `initState`).
DeviceKind get currentDeviceKind {
  final view = _appView;
  return deviceKindFor(
    view == null ? Size.zero : view.physicalSize / view.devicePixelRatio,
  );
}

/// Densidade da tela do app (1 sem janela).
double get currentPixelRatio => _appView?.devicePixelRatio ?? 1;

/// A janela do app: a do binding (que os testes de widget redimensionam) ou,
/// sem binding (código chamado de um teste de Dart puro), a do `dart:ui`.
ui.FlutterView? get _appView {
  try {
    return WidgetsBinding.instance.platformDispatcher.implicitView;
  } on FlutterError {
    return ui.PlatformDispatcher.instance.implicitView;
  }
}

/// Como os textos chamam o aparelho: "celular" no celular (onde o app
/// nasceu e a maioria dos textos foi escrita), "tablet" e "computador"
/// (desktop e navegador).
String deviceNoun(BuildContext context) => switch (deviceKindOf(context)) {
  DeviceKind.phone => 'celular',
  DeviceKind.tablet => 'tablet',
  DeviceKind.desktop => 'computador',
};
