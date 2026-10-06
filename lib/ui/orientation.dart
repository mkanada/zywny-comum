import 'package:flutter/services.dart';

/// Retrato ou paisagem, conforme o aparelho está (sem de cabeça para baixo):
/// a biblioteca e o fluxo de cursos inteiro (lista, curso, lição, exercício).
/// Com o teclado ligado por cabo no celular, girar o aparelho a cada tela
/// incomodava. Só a partitura do hino trava em paisagem.
const kFollowDeviceOrientations = [
  DeviceOrientation.portraitUp,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];
