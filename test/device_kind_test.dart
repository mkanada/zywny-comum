// Celular, tablet ou computador: o tipo de aparelho e como os textos o chamam.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zywny/ui/device_kind.dart';

Future<(DeviceKind, String)> _at(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late DeviceKind kind;
  late String noun;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          kind = deviceKindOf(context);
          noun = deviceNoun(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return (kind, noun);
}

void main() {
  testWidgets('Android: celular em pé ou deitado, tablet de tela grande', (
    tester,
  ) async {
    expect(await _at(tester, const Size(411, 866)), (
      DeviceKind.phone,
      'celular',
    ));
    expect(await _at(tester, const Size(866, 411)), (
      DeviceKind.phone,
      'celular',
    ));
    expect(await _at(tester, const Size(820, 1180)), (
      DeviceKind.tablet,
      'tablet',
    ));
    expect(await _at(tester, const Size(1180, 820)), (
      DeviceKind.tablet,
      'tablet',
    ));
    // Sem contexto (initState), pela janela do app.
    expect(currentDeviceKind, DeviceKind.tablet);
  });

  testWidgets('desktop e navegador: computador, mesmo numa janela estreita', (
    tester,
  ) async {
    expect(await _at(tester, const Size(1440, 900)), (
      DeviceKind.desktop,
      'computador',
    ));
    expect(await _at(tester, const Size(400, 800)), (
      DeviceKind.desktop,
      'computador',
    ));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
