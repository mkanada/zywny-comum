// "Sobre o Zywny": a origem do nome, os objetivos, a versão e as licenças.

import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:zywny/about/about_screen.dart';
import 'package:zywny/about/licenses.dart';
import 'package:zywny/ui/theme.dart';

void main() {
  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpAbout(
    WidgetTester tester, {
    String version = 'Versão 1.0.3 (4)',
    void Function(BuildContext, String)? openLicenses,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AboutScreen(
          loadVersion: () async => version,
          openLicenses: openLicenses ?? (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('conta de onde vem o nome', (tester) async {
    useSize(tester, const Size(390, 844));
    await pumpAbout(tester);

    expect(find.text('Sobre o Zywny'), findsOneWidget);
    expect(find.text('De onde vem o nome'), findsOneWidget);
    expect(find.textContaining('Wojciech Żywny (1756–1842)'), findsOneWidget);
    expect(find.textContaining('Frédéric Chopin'), findsOneWidget);
    // As fontes divergem sobre quando as aulas acabaram: o texto não fixa.
    expect(find.textContaining('a partir de 1816'), findsOneWidget);
    expect(find.textContaining('1822'), findsNothing);
    expect(find.textContaining('homenagem'), findsOneWidget);
    expect(find.textContaining('JÍV-ni'), findsOneWidget);
  });

  testWidgets('diz o que o app quer ser, um objetivo por item', (tester) async {
    useSize(tester, const Size(390, 844));
    await pumpAbout(tester);
    expect(find.text('O que o Zywny quer ser'), findsOneWidget);
    for (final lead in [
      'Treinar no seu teclado.',
      'Ensinar do zero.',
      'Estudar com método.',
      'Trazer a sua música.',
      'Estar onde você estiver.',
    ]) {
      expect(
        find.textContaining(lead, findRichText: true),
        findsOneWidget,
        reason: lead,
      );
    }
  });

  testWidgets('o cabeçalho tem o lema e a versão', (tester) async {
    useSize(tester, const Size(390, 844));
    await pumpAbout(tester);
    expect(
      find.text('Todo grande pianista começou na primeira tecla.'),
      findsOne,
    );
    expect(find.text('Versão 1.0.3 (4)'), findsOneWidget);
  });

  testWidgets('sem versão conhecida, o cabeçalho não mostra nada no lugar', (
    tester,
  ) async {
    useSize(tester, const Size(390, 844));
    await pumpAbout(tester, version: '');
    expect(find.textContaining('Versão'), findsNothing);
  });

  testWidgets('o botão abre as licenças, com a versão', (tester) async {
    useSize(tester, const Size(390, 844));
    String? version;
    await pumpAbout(tester, openLicenses: (_, v) => version = v);
    await tester.scrollUntilVisible(
      find.text('Licenças de código aberto'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Licenças de código aberto'));
    expect(version, 'Versão 1.0.3 (4)');
  });

  testWidgets('a página de licenças de verdade abre', (tester) async {
    useSize(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AboutScreen(loadVersion: () async => '1.0'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Licenças de código aberto'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Licenças de código aberto'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Zywny'), findsWidgets);
  });

  for (final size in const [
    Size(320, 568), // celular pequeno em pé
    Size(844, 390), // celular deitado
    Size(1280, 800), // desktop
  ]) {
    testWidgets('cabe em ${size.width.toInt()}×${size.height.toInt()}, '
        'também com a fonte do sistema grande', (tester) async {
      useSize(tester, size);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpAbout(tester);
      await tester.scrollUntilVisible(
        find.text('Licenças de código aberto'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }

  group('versão do aparelho', () {
    test('formata versão e número da compilação', () async {
      PackageInfo.setMockInitialValues(
        appName: 'zywny',
        packageName: 'br.zywny',
        version: '1.0.3',
        buildNumber: '4',
        buildSignature: '',
      );
      expect(await packageVersionText(), 'Versão 1.0.3 (4)');
    });

    test('sem número da compilação, só a versão', () async {
      PackageInfo.setMockInitialValues(
        appName: 'zywny',
        packageName: 'br.zywny',
        version: '2.1.0',
        buildNumber: '',
        buildSignature: '',
      );
      expect(await packageVersionText(), 'Versão 2.1.0');
    });
  });

  group('licença do soundfont', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    tearDown(LicenseRegistry.reset);

    test('a página de licenças ganha o aviso do TimGM6mb', () async {
      registerBundledLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      final soundfont = entries.where(
        (e) => e.packages.contains('TimGM6mb (som do piano)'),
      );
      expect(soundfont, hasLength(1));
      final text = soundfont.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('GPL'));
      expect(text, contains('Tim Brechbill'));
    });

    test('o aviso viaja no app (está declarado nos assets)', () async {
      final text = await rootBundle.loadString(
        'assets/soundfonts/TimGM6mb.copyright',
      );
      expect(text, contains('GPL-2'));
    });
  });
}
