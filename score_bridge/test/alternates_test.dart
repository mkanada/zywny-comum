// Modelo, parser e geometria das sequências alternativas (P03a, §2.5).
//
// `maple-leaf-rag.vsb` foi regenerado em P03a com `-x 42` sobre o binário já
// com P02c (8 sequências alternativas medidas em P02c), para os critérios 1
// e 3 usarem fixtures reais. `erik-satie.vsb` continua sem `alternates.json`
// (fixture de antes de P02c) e serve o critério 2 (leitor antigo, sem o
// arquivo, dá `alternates` vazia).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

VsbDocument _fixture(String name) =>
    VsbDocument.fromBytes(File('test/fixtures/$name').readAsBytesSync());

/// Primeiro nó de classe `measure` em pré-ordem, como a regra de §5.5/P02c
/// já usa no lado C++ — reimplementada aqui só para verificar o parser, não
/// para reproduzir nenhuma lógica de produção.
String? _firstMeasureId(SceneNode node) {
  if (node.className.split(' ').contains('measure')) return node.id;
  for (final child in node.children) {
    if (child is SceneNode) {
      final found = _firstMeasureId(child);
      if (found != null) return found;
    }
  }
  return null;
}

void main() {
  group('maple-leaf-rag.vsb (com alternativas, P02c)', () {
    late VsbDocument doc;

    setUpAll(() {
      doc = _fixture('maple-leaf-rag.vsb');
    });

    test('critério 1: 8 sequências, cada página 0 começa com "start"', () {
      expect(doc.alternates, hasLength(8));
      for (final sequence in doc.alternates) {
        expect(sequence.pages, isNotEmpty);
        expect(_firstMeasureId(sequence.pages.first.root), sequence.start);
      }
    });

    test('alternateStartingAt encontra a sequência certa, e só ela', () {
      final first = doc.alternates.first;
      expect(doc.alternateStartingAt(first.start), same(first));
      expect(doc.alternateStartingAt('id-que-nao-existe'), isNull);
    });

    test('critério 3: geometryOf(k) devolve a página/bbox da sequência k, '
        'diferente das normais', () {
      final sequence = doc.alternates.first;
      final noteId = 'm15xbieh'; // 1ª nota da página 0 da sequência 0
      expect(sequence.start, 'q1t6l0ej');

      final inSequence = doc.geometryOf(0).elementOf(noteId);
      expect(inSequence, isNotNull);
      expect(inSequence!.page, 0); // página 0 **dentro da sequência**

      // A mesma nota, pela geometria normal: mesmo id, página bem diferente
      // (a sequência começa no meio da peça) — ou nem aparece nas páginas
      // normais, se a nota só existir a partir do compasso de chegada em
      // diante nesta região específica da árvore (não é o caso aqui, mas o
      // teste não deve presumir).
      final normal = doc.geometry.elementOf(noteId);
      if (normal != null) {
        expect(
          inSequence.bbox == normal.bbox && inSequence.page == normal.page,
          isFalse,
          reason:
              'a bbox/página da sequência não pode ser confundida com '
              'a das páginas normais',
        );
      }
    });

    test('pageAt resolve PageRef normal e alternativo', () {
      final normalPage0 = doc.pageAt(const PageRef(0));
      expect(normalPage0, same(doc.pages[0]));

      final altPage0 = doc.pageAt(const PageRef(0, sequence: 0));
      expect(altPage0, same(doc.alternates[0].pages[0]));
    });

    test('PageRef: igualdade, hashCode e isAlternate', () {
      expect(const PageRef(0), const PageRef(0));
      expect(const PageRef(0, sequence: 1), const PageRef(0, sequence: 1));
      expect(const PageRef(0), isNot(const PageRef(1)));
      expect(const PageRef(0), isNot(const PageRef(0, sequence: 0)));
      expect(const PageRef(0).isAlternate, isFalse);
      expect(const PageRef(0, sequence: 0).isAlternate, isTrue);
      expect(
        const PageRef(0, sequence: 1).hashCode,
        const PageRef(0, sequence: 1).hashCode,
      );
    });
  });

  group('erik-satie.vsb (sem alternates.json, fixture de antes de P02c)', () {
    test('critério 2: alternates vazia, nada mais muda', () {
      final doc = _fixture('erik-satie.vsb');
      expect(doc.alternates, isEmpty);
      expect(doc.manifest.files.alternates, isNull);
      // document.pages e document.geometry continuam intactos.
      expect(doc.pages, hasLength(2));
      expect(doc.geometry.length, greaterThan(0));
    });
  });

  test('exemplo-alternates.json (P02a) parseia (critério 5)', () {
    final file = File('../docs/formato/exemplo-alternates.json');
    final decoded =
        json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    final sequences = parseAlternatesDocument(decoded, path: 'alternates');
    expect(sequences, hasLength(1));
    expect(sequences.single.start, 'm5');
    expect(sequences.single.pages, hasLength(1));
    expect(_firstMeasureId(sequences.single.pages.single.root), 'm5');
  });
}
