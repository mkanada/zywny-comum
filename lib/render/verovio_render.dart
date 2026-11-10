import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:score_bridge/score_bridge.dart';
import 'package:verovio/verovio.dart';

import 'music_snapshot_result.dart';
import 'verovio_gate.dart';

export 'music_snapshot_result.dart';
export 'page_size.dart';

/// All inputs for one render job: the whole score as a single `.vsb`
/// (Verovio Score Bridge package: `scene.json` + `glyphs.json` +
/// `timemap.json` in a zip), written to [outputPath]. Transferable across
/// isolates as a Map.
class VsbRenderRequest {
  VsbRenderRequest({
    required this.inputPath,
    required this.outputPath,
    required this.libraryPath,
    required this.resourcePath,
    required this.pageWidth,
    required this.pageHeight,
    this.options = const {},
  });

  final String inputPath;
  final String outputPath;
  final String libraryPath;
  final String resourcePath;
  final int pageWidth;
  final int pageHeight;

  /// Further Verovio options (`layout_options.dart`), applied after the page
  /// size; whatever is not listed keeps Verovio's default.
  final Map<String, Object> options;

  Map<String, Object?> toJson() => {
    'inputPath': inputPath,
    'outputPath': outputPath,
    'libraryPath': libraryPath,
    'resourcePath': resourcePath,
    'pageWidth': pageWidth,
    'pageHeight': pageHeight,
    'options': options,
  };
}

/// Renders the whole score to a single `.vsb` in a worker isolate — so the
/// UI thread never blocks on the native call — and parses the result.
///
/// A [VerovioToolkit] wraps a native pointer and must be constructed, used
/// and disposed inside the same isolate — hence everything native happens
/// in [_renderInIsolate], which only hands back a file path. The parse runs
/// here, on the caller's isolate: the model it builds (`ui.Rect`/`ui.Offset`
/// and the glyph cache's `ui.Path`s) belongs to the isolate that paints it.
///
/// Renders go through [verovioGate]: one at a time by default, and ABC always
/// alone. Verovio keeps ABC parser state in process-wide globals (`ioabc.cpp`:
/// `abcLine`, `dataKey`, `keyPitchAlter`…), so two isolates loading ABC at once
/// corrupt each other and abort the app with `std::out_of_range` — a lesson
/// with two ABC scores did exactly that on the phone. MusicXML/MEI may run in
/// parallel once the caller raises `verovioGate.parallelism` (its ids are
/// `thread_local`).
Future<VsbDocument> renderScoreToVsb(VsbRenderRequest request) async {
  await verovioGate.run(
    () => Isolate.run(() => _renderInIsolate(request.toJson())),
    exclusive: !verovioSafeInParallel(request.inputPath),
  );
  final bytes = await File(request.outputPath).readAsBytes();
  _assertVsbPackage(request.outputPath, bytes);
  return VsbDocument.fromBytes(bytes);
}

void _renderInIsolate(Map<String, Object?> json) {
  final inputPath = json['inputPath'] as String;
  final outputPath = json['outputPath'] as String;
  final libraryPath = json['libraryPath'] as String;
  final resourcePath = json['resourcePath'] as String;
  final pageWidth = json['pageWidth'] as int;
  final pageHeight = json['pageHeight'] as int;
  final options = (json['options'] as Map).cast<String, Object>();

  final toolkit = VerovioToolkit.withResourcePath(
    resourcePath,
    libraryPath: libraryPath,
  );
  try {
    // Options must be set BEFORE loading: page size only takes effect
    // on the layout triggered by the load.
    final optionsSet = toolkit.setOptions(
      jsonEncode({
        'pageWidth': pageWidth,
        'pageHeight': pageHeight,
        ...options,
      }),
    );
    if (!optionsSet) {
      throw StateError(
        'Verovio rejected the layout options\n${toolkit.getLog()}',
      );
    }
    // Must come before loadFile: the bridge's own layout defaults (no
    // header, no footer, no instrument labels — Toolkit::ApplyBridgeDefaults,
    // score_bridge P01b) only kick in while the output format is already
    // vsb/vsb-json, and all three affect cast-off, not just drawing.
    if (!toolkit.setOutputTo('vsb')) {
      throw StateError(
        'Verovio rejected output format vsb\n${toolkit.getLog()}',
      );
    }
    if (!toolkit.loadFile(inputPath)) {
      throw StateError(
        'Verovio could not load $inputPath\n${toolkit.getLog()}',
      );
    }
    // Whole score: every page in one package, timemap included (-t vsb).
    if (!toolkit.renderToBridgeFile(outputPath)) {
      throw StateError(
        'Verovio could not render $outputPath\n${toolkit.getLog()}',
      );
    }
  } finally {
    toolkit.dispose();
  }
}

/// O retrato do Verovio de [inputPath] para quem mede a música (T18, LP01): o
/// JSON do bridge (`renderToBridgeJson`: cena, timemap, MIDI, contexto de
/// notação) e os atributos (`getElementAttr`) dos elementos `measure`, `staff`,
/// `layer` e `note` da cena. Os atributos saem pedidos aqui, de antemão, porque o
/// Verovio mora neste isolate e quem mede a música não chega até ele.
///
/// [options] são as da partitura desenhada (`xmlIdSeed`, `transpose`): é isso que
/// faz os ids das notas baterem com os do desenho. Passa pela mesma fila de
/// [renderScoreToVsb], porque o Verovio guarda estado global.
Future<MusicSnapshotResult> readScoreMusic({
  required String inputPath,
  required String libraryPath,
  required String resourcePath,
  Map<String, Object> options = const {},
}) async {
  final json = await verovioGate.run(
    () => Isolate.run(
      () => _readMusicInIsolate({
        'inputPath': inputPath,
        'libraryPath': libraryPath,
        'resourcePath': resourcePath,
        'options': options,
      }),
    ),
    exclusive: !verovioSafeInParallel(inputPath),
  );
  return MusicSnapshotResult(json);
}

/// A opção (que o Verovio não conhece) que pede, junto do retrato, o MEI e o
/// `music.json` da música: o `zywny-aprendizado` gera o baixo com eles (LM16).
/// Só a leitura nativa a atende; a Web ainda não.
const musicDerivationOption = 'musicDerivation';

/// Os elementos da cena de que o medidor pede atributos. A lista é a
/// `kMusicAttributeClasses` do `zywny-aprendizado` (`music_verovio.dart`); o
/// comum não importa o app, então ela foi copiada: mudou numa, mude na outra.
const _musicAttributeClasses = {'measure', 'staff', 'layer', 'note'};

/// Mesma sequência de [_renderInIsolate] (opções antes de carregar, `vsb` como
/// formato de saída, `loadFile`): os ids nascem no carregamento, e carregar do
/// mesmo jeito que o desenho é o que os deixa iguais.
String _readMusicInIsolate(Map<String, Object?> json) {
  final inputPath = json['inputPath'] as String;
  final libraryPath = json['libraryPath'] as String;
  final resourcePath = json['resourcePath'] as String;
  final allOptions = (json['options'] as Map).cast<String, Object>();
  // `musicDerivation` não é do Verovio: pede o MEI e o `music.json` (cifras) da
  // música carregada, para o aprendizado gerar o baixo (T18, LM16).
  final derivation = allOptions[musicDerivationOption] == true;
  final options = {...allOptions}..remove(musicDerivationOption);

  final toolkit = VerovioToolkit.withResourcePath(
    resourcePath,
    libraryPath: libraryPath,
  );
  try {
    if (!toolkit.setOptions(jsonEncode(options))) {
      throw StateError(
        'Verovio rejected the layout options\n${toolkit.getLog()}',
      );
    }
    if (!toolkit.setOutputTo('vsb')) {
      throw StateError(
        'Verovio rejected output format vsb\n${toolkit.getLog()}',
      );
    }
    if (!toolkit.loadFile(inputPath)) {
      throw StateError(
        'Verovio could not load $inputPath\n${toolkit.getLog()}',
      );
    }
    final bridge = toolkit.renderToBridgeJson();
    final decoded = jsonDecode(bridge);
    final attributes = <String, Map<String, String>>{};
    void walk(Object? node) {
      if (node is Map) {
        final id = node['id'];
        if (id is String && _musicAttributeClasses.contains(node['class'])) {
          final attrs = _attributesOf(toolkit.getElementAttr(id));
          if (attrs.isNotEmpty) attributes[id] = attrs;
        }
        walk(node['children']);
        walk(node['pages']);
        walk(node['root']);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    if (decoded is Map) walk(decoded['scene']);
    return jsonEncode({
      'bridge': bridge,
      'attributes': attributes,
      if (derivation) 'music': toolkit.renderToMusicJson(),
      if (derivation) 'mei': toolkit.getMEI(),
    });
  } finally {
    toolkit.dispose();
  }
}

/// O `getElementAttr` devolve um objeto JSON (ou texto vazio, sem atributos).
Map<String, String> _attributesOf(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const {};
  final decoded = jsonDecode(trimmed);
  if (decoded is! Map) return const {};
  return {
    for (final entry in decoded.entries) '${entry.key}': '${entry.value}',
  };
}

void _assertVsbPackage(String path, Uint8List bytes) {
  // The renderer only signals success/failure; verify the artifact is really
  // a `.vsb` (zip) package so a broken file fails here with a clear message
  // instead of deep inside the parser.
  if (bytes.length < 4 ||
      bytes[0] != 0x50 ||
      bytes[1] != 0x4B ||
      bytes[2] != 0x03 ||
      bytes[3] != 0x04) {
    throw StateError(
      'Render produced ${bytes.length} bytes without the zip/.vsb '
      'magic (PK\\x03\\x04): $path',
    );
  }
}
