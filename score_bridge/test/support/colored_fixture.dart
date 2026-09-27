// Fixtures derivados do `erik-satie.vsb` para os testes de cor (A01c/A02).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:score_bridge/score_bridge.dart';

/// O `erik-satie.vsb` do repositório, sem alteração.
VsbDocument loadSatie() => VsbDocument.fromBytes(
  File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
);

/// O mesmo documento com `"color": hex` gravado nos nós de [ids] — o que o
/// exportador faz com `@color` no MEI. O corpus não tem nenhuma peça
/// colorida, então o fixture é fabricado aqui.
VsbDocument loadSatieWithColors(Map<String, String> colorById) {
  final archive = ZipDecoder().decodeBytes(
    File('test/fixtures/erik-satie.vsb').readAsBytesSync(),
  );
  final scene = json.decode(
    utf8.decode(archive.findFile('scene.json')!.readBytes()!),
  ) as Map<String, dynamic>;
  var painted = 0;
  void visit(Object? node) {
    if (node is! Map<String, dynamic>) {
      return;
    }
    final color = colorById[node['id']];
    if (color != null) {
      node['color'] = color;
      painted++;
    }
    for (final child in (node['children'] as List<dynamic>?) ?? const []) {
      visit(child);
    }
  }

  for (final page in scene['pages'] as List<dynamic>) {
    visit((page as Map<String, dynamic>)['root']);
  }
  if (painted != colorById.length) {
    throw StateError('só $painted de ${colorById.length} ids encontrados');
  }
  final out = Archive();
  for (final file in archive.files) {
    final bytes = file.name == 'scene.json'
        ? Uint8List.fromList(utf8.encode(json.encode(scene)))
        : file.readBytes()!;
    out.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }
  return VsbDocument.fromBytes(Uint8List.fromList(ZipEncoder().encode(out)));
}

/// Percorre [node] em pré-ordem.
Iterable<SceneNode> descendants(SceneNode node) sync* {
  yield node;
  for (final child in node.children) {
    if (child is SceneNode) {
      yield* descendants(child);
    }
  }
}

/// Notas da página com haste (`stem`) e id no timemap, em ordem de documento.
List<SceneNode> notesWithStem(VsbDocument doc, int pageIndex) {
  final animatable = animatableIdsFromTimemap(doc.timemap);
  return [
    for (final node in descendants(doc.pages[pageIndex].root))
      if (node.className == 'note' &&
          !node.hidden &&
          animatable.contains(node.id) &&
          descendants(node).any((n) => n.className == 'stem'))
        node,
  ];
}
