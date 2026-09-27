// Renderização de uma página por dois caminhos, para os testes de A01/A02.
//
// `harnessBytes` é o "passada única" do `compare scene-to-png` (fundo branco
// opaco + `ScenePainter.paint`); `widgetBytes` captura um widget dentro de um
// `RepaintBoundary` com `pixelRatio: 1.0`. Ambos devolvem RGBA cru.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

/// Diretório dos pacotes do corpus (git-ignorado; regenerável).
const kCorpusDir = '../compare/out/s08';

/// Os `.vsb` do corpus, ordenados; vazio se o diretório não existe.
List<File> corpusFiles() {
  final dir = Directory(kCorpusDir);
  if (!dir.existsSync()) {
    return const [];
  }
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.vsb'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

Future<ByteData> _toBytes(WidgetTester tester, ui.Image image) async {
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  return bytes!;
}

/// Caminho de passada única (o do harness `scene-to-png`).
Future<ByteData> harnessBytes(
  WidgetTester tester,
  VsbDocument doc,
  int pageIndex,
) async {
  final page = doc.pages[pageIndex];
  final w = page.widthPx;
  final h = page.heightPx;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  ScenePainter(page, doc.glyphs).paint(canvas);
  final picture = recorder.endRecording();
  final image = (await tester.runAsync(() => picture.toImage(w, h)))!;
  final bytes = await _toBytes(tester, image);
  picture.dispose();
  image.dispose();
  return bytes;
}

/// Monta [widget] numa janela de exatamente `w × h` (dpr 1).
Future<GlobalKey> pumpAtSize(
  WidgetTester tester,
  Widget widget,
  int w,
  int h,
) async {
  tester.view.physicalSize = ui.Size(w.toDouble(), h.toDouble());
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(key: key, child: widget),
    ),
  );
  await tester.pump();
  return key;
}

/// Captura a região do [key] como RGBA cru, `w × h`.
Future<ByteData> captureBytes(
  WidgetTester tester,
  GlobalKey key,
  int w,
  int h,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: 1.0),
  ))!;
  expect(image.width, w);
  expect(image.height, h);
  final bytes = await _toBytes(tester, image);
  image.dispose();
  return bytes;
}

/// Pixels com algum canal RGBA diferente.
int countDifferentPixels(ByteData a, ByteData b) {
  expect(a.lengthInBytes, b.lengthInBytes);
  final ra = a.buffer.asUint8List(a.offsetInBytes, a.lengthInBytes);
  final rb = b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
  var diff = 0;
  for (var i = 0; i < ra.length; i += 4) {
    if (ra[i] != rb[i] ||
        ra[i + 1] != rb[i + 1] ||
        ra[i + 2] != rb[i + 2] ||
        ra[i + 3] != rb[i + 3]) {
      diff++;
    }
  }
  return diff;
}

/// Renderiza o `ScorePageView` da página e devolve o RGBA cru.
Future<ByteData> pageViewBytes(
  WidgetTester tester,
  VsbDocument doc,
  int pageIndex, {
  ScoreController? controller,
  Set<String>? animatableIds,
}) async {
  final page = doc.pages[pageIndex];
  final key = await pumpAtSize(
    tester,
    ScorePageView(
      document: doc,
      pageIndex: pageIndex,
      controller: controller,
      animatableIds: animatableIds,
    ),
    page.widthPx,
    page.heightPx,
  );
  return captureBytes(tester, key, page.widthPx, page.heightPx);
}

/// Renderiza um `ScoreView` numa janela do tamanho da página [pageIndex] e
/// devolve o RGBA cru; o widget continua montado (o chamador desmonta).
Future<({GlobalKey key, int w, int h})> pumpView(
  WidgetTester tester,
  Widget view,
  ScenePage page,
) async {
  final key = await pumpAtSize(tester, view, page.widthPx, page.heightPx);
  return (key: key, w: page.widthPx, h: page.heightPx);
}

/// O `.vsb` do corpus cujo nome contém [part]; `null` se não existir.
VsbDocument? corpusDoc(String part) {
  for (final f in corpusFiles()) {
    if (f.path.contains(part)) {
      return VsbDocument.fromBytes(f.readAsBytesSync());
    }
  }
  return null;
}

/// Conta pixels "vermelho de destaque" (`0xD32F2F`, tolerância larga) em
/// [rect] da imagem `w × h`.
int countRedPixels(ByteData bytes, int w, ui.Rect rect) {
  final data = bytes.buffer.asUint8List(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  var n = 0;
  for (var y = rect.top.floor(); y < rect.bottom.ceil(); y++) {
    for (var x = rect.left.floor(); x < rect.right.ceil(); x++) {
      final i = (y * w + x) * 4;
      if (data[i] > 150 && data[i + 1] < 110 && data[i + 2] < 110) {
        n++;
      }
    }
  }
  return n;
}

/// RGBA `(r, g, b)` do pixel `(x, y)` da imagem de largura [w].
(int, int, int) pixelAt(ByteData bytes, int w, int x, int y) {
  final i = (y * w + x) * 4;
  return (bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
}

/// Grava [bytes] (RGBA `w × h`) como PNG em [path], para as evidências.
Future<void> writePng(
  WidgetTester tester,
  ByteData bytes,
  int w,
  int h,
  String path,
) async {
  await tester.runAsync(() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final desc = ui.ImageDescriptor.raw(
      buffer,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
    frame.image.dispose();
    codec.dispose();
    desc.dispose();
    buffer.dispose();
  });
}
