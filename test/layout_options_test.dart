// A tabela de opções do painel (lib/layout_options.dart) contra o Verovio de
// verdade: chaves, tipos, padrões, faixas e listas de escolha vêm de
// `getAvailableOptions()`, e alguns renders mostram que o exportador `.vsb`
// respeita as opções — em especial `unit`, que refaz o layout, ao contrário
// de `scale`, que só muda o tamanho de saída da página.
//
// A parte nativa é pulada, como em vsb_render_test.dart, quando a
// libverovio.so ou o submódulo não estão presentes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verovio/verovio.dart';
import 'package:zywny/layout_options.dart';
import 'package:zywny/verovio_render.dart';

const _submodule = '/home/mauricio/rust_projects/verovio_flutter_bridge';
const _libPath = '$_submodule/verovio/bindings/dart/libverovio.so';
const _resourcePath = '$_submodule/verovio/data';
const _scorePath = '$_submodule/corpus/mei/Grieg_Little_bird_Op43_No4.mei';

/// Finds the metadata object of option [key] anywhere in the (grouped)
/// `getAvailableOptions()` tree.
Map<String, dynamic>? _find(Object? node, String key) {
  if (node is Map<String, dynamic>) {
    if (node[key] is Map<String, dynamic>) {
      return node[key] as Map<String, dynamic>;
    }
    for (final v in node.values) {
      final found = _find(v, key);
      if (found != null) return found;
    }
  }
  return null;
}

Iterable<LayoutOption> get _allOptions =>
    kLayoutGroups.expand((g) => g.options);

void main() {
  group('layoutOptionsToSend', () {
    test('o estado inicial só desvia do Verovio no rodapé', () {
      expect(layoutOptionsToSend(initialLayoutValues()), {'footer': 'none'});
    });

    test(
      'envia só o que difere do padrão e deixa o tamanho da página fora',
      () {
        final values = initialLayoutValues()
          ..['unit'] = 7.5
          ..['breaks'] = 'none'
          ..['justifyVertically'] = true
          ..['pageWidth'] =
              2100 // fora: viaja como tamanho da página
          ..['marginHorizontal'] = 50; // igual ao padrão: fora
        expect(layoutOptionsToSend(values), {
          'footer': 'none',
          'unit': 7.5,
          'breaks': 'none',
          'justifyVertically': true,
        });
      },
    );

    test('uma margem unificada vai para as duas opções do Verovio', () {
      final values = initialLayoutValues()
        ..['marginHorizontal'] = 80
        ..['marginVertical'] = 20;
      expect(layoutOptionsToSend(values), {
        'footer': 'none',
        'pageMarginLeft': 80,
        'pageMarginRight': 80,
        'pageMarginTop': 20,
        'pageMarginBottom': 20,
      });
    });

    test('chaves são únicas', () {
      final keys = _allOptions.map((o) => o.key).toList();
      expect(keys.toSet().length, keys.length);
    });
  });

  final missing = [
    _libPath,
    _resourcePath,
    _scorePath,
  ].where((p) => !File(p).existsSync() && !Directory(p).existsSync()).toList();
  final skip = missing.isEmpty
      ? null
      : 'artefatos ausentes: ${missing.join(', ')}';

  test('a tabela confere com getAvailableOptions() do Verovio', () {
    final toolkit = VerovioToolkit.withResourcePath(
      Directory(_resourcePath).absolute.path,
      libraryPath: File(_libPath).absolute.path,
    );
    final Object? available;
    try {
      available = jsonDecode(toolkit.getAvailableOptions());
    } finally {
      toolkit.dispose();
    }

    for (final option in _allOptions) {
      for (final key in option.verovioKeys.skip(1)) {
        expect(
          _find(available, key),
          isNotNull,
          reason: '$key: ausente no Verovio',
        );
      }
      final meta = _find(available, option.verovioKeys.first);
      expect(meta, isNotNull, reason: '${option.key}: ausente no Verovio');
      meta!;
      switch (option.kind) {
        case LayoutOptionKind.integer:
          expect(meta['type'], 'int', reason: option.key);
        case LayoutOptionKind.decimal:
          expect(meta['type'], 'double', reason: option.key);
        case LayoutOptionKind.toggle:
          expect(meta['type'], 'bool', reason: option.key);
        case LayoutOptionKind.choice:
          expect(meta['type'], startsWith('std::string'), reason: option.key);
      }

      if (option.defaultValue is num) {
        expect(
          option.defaultValue as num,
          closeTo(meta['default'] as num, 1e-9),
          reason: '${option.key}: padrão',
        );
      } else {
        expect(
          option.defaultValue,
          meta['default'],
          reason: '${option.key}: padrão',
        );
      }

      if (option.kind == LayoutOptionKind.integer ||
          option.kind == LayoutOptionKind.decimal) {
        expect(
          option.min,
          closeTo(meta['min'] as num, 1e-9),
          reason: '${option.key}: mínimo',
        );
        expect(
          option.max,
          closeTo(meta['max'] as num, 1e-9),
          reason: '${option.key}: máximo',
        );
        final soft = option.softMax;
        if (soft != null) {
          expect(
            soft,
            inInclusiveRange(option.min, option.max),
            reason: '${option.key}: softMax fora da faixa',
          );
        }
      }

      if (meta['type'] == 'std::string-list') {
        expect(
          option.choices,
          meta['values'],
          reason: '${option.key}: escolhas',
        );
      }
      if (option.choices.isNotEmpty) {
        expect(
          option.choices,
          contains(option.defaultValue),
          reason: '${option.key}: o padrão não está nas escolhas',
        );
      }
    }

    // As fontes do painel têm de existir nos dados empacotados.
    final fonts = kLayoutGroups
        .expand((g) => g.options)
        .firstWhere((o) => o.key == 'font')
        .choices;
    for (final font in fonts) {
      expect(
        Directory('$_resourcePath/$font').existsSync(),
        isTrue,
        reason: 'fonte $font sem dados em $_resourcePath',
      );
    }
  }, skip: skip);

  group('render com opções', () {
    late Directory tmp;
    setUpAll(
      () async => tmp = await Directory.systemTemp.createTemp('zywny_opt'),
    );
    tearDownAll(() => tmp.delete(recursive: true));

    var n = 0;
    Future<int> pagesWith(Map<String, Object> options) async {
      final document = await renderScoreToVsb(
        VsbRenderRequest(
          inputPath: _scorePath,
          outputPath: '${tmp.path}/${n++}.vsb',
          libraryPath: File(_libPath).absolute.path,
          resourcePath: Directory(_resourcePath).absolute.path,
          pageWidth: kFallbackPageWidth,
          pageHeight: kFallbackPageHeight,
          options: options,
        ),
      );
      return document.pages.length;
    }

    test('unit refaz o layout: notação maior, mais páginas', () async {
      final small = await pagesWith({'unit': 6.0});
      final normal = await pagesWith({});
      final large = await pagesWith({'unit': 12.0});
      expect(small, lessThan(normal));
      expect(normal, lessThan(large));
    }, skip: skip);

    test('breaks: none põe a peça inteira numa página só', () async {
      expect(await pagesWith({'breaks': 'none'}), 1);
    }, skip: skip);

    test('margens e espaçamento chegam ao layout', () async {
      final normal = await pagesWith({});
      expect(
        await pagesWith({'pageMarginLeft': 300, 'pageMarginRight': 300}),
        greaterThan(normal),
      );
      expect(await pagesWith({'spacingLinear': 1.0}), greaterThan(normal));
    }, skip: skip);

    test('as opções do estado inicial do app renderizam', () async {
      expect(
        await pagesWith(layoutOptionsToSend(initialLayoutValues())),
        greaterThan(0),
      );
    }, skip: skip);
  });
}
