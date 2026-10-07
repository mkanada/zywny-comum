import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:score_bridge/score_bridge.dart';
import 'package:verovio/verovio.dart';

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

/// Tail of the render chain; see [renderScoreToVsb].
Future<void> _renderQueue = Future.value();

/// Renders the whole score to a single `.vsb` in a worker isolate — so the
/// UI thread never blocks on the native call — and parses the result.
///
/// A [VerovioToolkit] wraps a native pointer and must be constructed, used
/// and disposed inside the same isolate — hence everything native happens
/// in [_renderInIsolate], which only hands back a file path. The parse runs
/// here, on the caller's isolate: the model it builds (`ui.Rect`/`ui.Offset`
/// and the glyph cache's `ui.Path`s) belongs to the isolate that paints it.
///
/// Renders run one at a time: Verovio keeps parser state in process-wide
/// globals (`ioabc.cpp`: `abcLine`, `dataKey`, `keyPitchAlter`…), so two
/// isolates loading ABC at once corrupt each other and abort the app with
/// `std::out_of_range` — a lesson with two ABC scores did exactly that on
/// the phone.
Future<VsbDocument> renderScoreToVsb(VsbRenderRequest request) async {
  final previous = _renderQueue;
  final done = Completer<void>();
  _renderQueue = done.future;
  try {
    await previous;
    await Isolate.run(() => _renderInIsolate(request.toJson()));
  } finally {
    done.complete();
  }
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
