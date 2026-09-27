// Casos de erro do parser (R01, critério de aceite 2).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

Map<String, dynamic> _loadExemploMinimo() {
  final file = File('../docs/formato/exemplo-minimo.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Clona o exemplo mínimo em memória para os testes poderem corromper uma
/// cópia sem afetar os outros testes (jsonDecode não compartilha estado
/// mutável entre chamadas).
Map<String, dynamic> _freshExemploMinimo() => _loadExemploMinimo();

void main() {
  test('version desconhecida lança UnsupportedVsbVersionException', () {
    final json = _freshExemploMinimo();
    (json['manifest'] as Map<String, dynamic>)['version'] = 999;

    expect(
      () => VsbDocument.fromJson(json),
      throwsA(
        isA<UnsupportedVsbVersionException>().having(
          (e) => e.version,
          'version',
          999,
        ),
      ),
    );
  });

  test('chave desconhecida em nó não lança', () {
    final json = _freshExemploMinimo();
    final root =
        (((json['scene'] as Map<String, dynamic>)['pages'] as List).single
                as Map<String, dynamic>)['root']
            as Map<String, dynamic>;
    root['umCampoNovoDoFuturo'] = 'valor qualquer';

    expect(() => VsbDocument.fromJson(json), returnsNormally);
  });

  test('chave desconhecida em forma não lança', () {
    final json = _freshExemploMinimo();
    final root =
        (((json['scene'] as Map<String, dynamic>)['pages'] as List).single
                as Map<String, dynamic>)['root']
            as Map<String, dynamic>;
    final staff = (root['children'] as List).first as Map<String, dynamic>;
    final pathShape = (staff['children'] as List).first as Map<String, dynamic>;
    pathShape['umCampoNovoDoFuturo'] = 42;

    expect(() => VsbDocument.fromJson(json), returnsNormally);
  });

  test(
    '"v" de comprimento ímpar lança VsbFormatException citando o caminho',
    () {
      final json = _freshExemploMinimo();
      final root =
          (((json['scene'] as Map<String, dynamic>)['pages'] as List).single
                  as Map<String, dynamic>)['root']
              as Map<String, dynamic>;
      final staff = (root['children'] as List).first as Map<String, dynamic>;
      final pathShape =
          (staff['children'] as List).first as Map<String, dynamic>;
      final firstSubpath =
          (pathShape['paths'] as List).first as Map<String, dynamic>;
      (firstSubpath['v'] as List).add(999); // 4 -> 5 elementos, ímpar.

      expect(
        () => VsbDocument.fromJson(json),
        throwsA(
          isA<VsbFormatException>().having(
            (e) => e.path,
            'path',
            'scene.pages[0].root.children[0].children[0].paths[0].v',
          ),
        ),
      );
    },
  );
}
