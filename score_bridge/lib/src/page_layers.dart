// Camadas de uma página: `ui.Picture` estáticos + pintura dinâmica ao vivo (A01b).
//
// Consome os segmentos de A01a. Cada `StaticSegment` é gravado **uma vez** num
// `ui.Picture` e reusado; cada `DynamicSegment` é pintado direto no canvas a
// cada repaint, com as cores do controller.
//
// DECISÃO DE ESPAÇO: os `Picture` são gravados em **unidades de viewBox**, no
// espaço de conteúdo (depois do `translate(fit)`/`scale`/`translate(origin)`
// da página, que é aplicado uma vez ao canvas de quem pinta — ver
// `ScenePainter.applyPageTransform`). Assim o cache é independente do tamanho
// do widget: redimensionar só muda a escala do canvas, não recompila nada, e
// o `Picture` reproduzido em outra escala continua vetorial. O cache só é
// invalidado quando muda documento, página ou o conjunto de ids dinâmicos —
// nunca por cor.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'glyph_cache.dart';
import 'model.dart';
import 'scene_painter.dart';
import 'segmentation.dart';

/// Contadores de instrumentação permanente dos `Picture` de uma página.
///
/// Compartilhado entre as gerações de [PageLayers] de um mesmo widget: é o
/// que prova, em A01 e A02, que trocar cor não recompila nada.
class PictureStats {
  /// `Picture` estáticos gravados (compilados) até agora.
  int builds = 0;

  /// `Picture` estáticos descartados (`dispose`) até agora.
  int disposals = 0;

  /// Tempo acumulado de gravação, em microssegundos.
  int buildMicroseconds = 0;

  /// `Picture` que ainda estão vivos.
  int get live => builds - disposals;
}

/// Os segmentos de uma página e o cache de `Picture` dos estáticos.
///
/// Imutável na estrutura: para mudar o conjunto de ids dinâmicos (ou de
/// página/documento) cria-se outro [PageLayers] e descarta-se este com
/// [dispose]. A gravação é preguiçosa (no primeiro [paint]) ou explícita
/// ([compileAll]).
class PageLayers {
  PageLayers(
    this.page,
    Map<String, GlyphDef> glyphs, {
    required Set<String> animatableIds,
    GlyphCache? glyphCache,
    PictureStats? stats,
  }) : stats = stats ?? PictureStats(),
       segments = segmentPage(page, animatableIds),
       _painter = ScenePainter(page, glyphs, glyphCache: glyphCache) {
    _pictures = List<ui.Picture?>.filled(segments.length, null);
  }

  final ScenePage page;

  /// Segmentação de A01a, calculada **uma vez** aqui.
  final List<PageSegment> segments;

  final PictureStats stats;
  final ScenePainter _painter;
  late final List<ui.Picture?> _pictures;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Grava agora todos os segmentos estáticos ainda não gravados.
  void compileAll() {
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] is StaticSegment) {
        _pictureAt(i);
      }
    }
  }

  ui.Picture _pictureAt(int index) {
    final cached = _pictures[index];
    if (cached != null) {
      return cached;
    }
    final watch = Stopwatch()..start();
    final segment = segments[index] as StaticSegment;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (final item in segment.items) {
      final transform = item.transform;
      if (transform == null) {
        _painter.paintLeaf(canvas, item.child, item.inheritedColor);
      } else {
        canvas.save();
        canvas.transform(transform.toMatrix4());
        _painter.paintLeaf(canvas, item.child, item.inheritedColor);
        canvas.restore();
      }
    }
    final picture = recorder.endRecording();
    stats.builds++;
    stats.buildMicroseconds += watch.elapsedMicroseconds;
    return _pictures[index] = picture;
  }

  /// Pinta a página no [canvas], **já no espaço de conteúdo**: chame
  /// `ScenePainter.applyPageTransform` antes (o `ScorePageView` faz).
  ///
  /// [colorOverrides] troca a cor de nós dinâmicos por `id`; os segmentos
  /// estáticos o ignoram por construção. [haloColors] (A02d) pinta, por trás
  /// da nota, o halo borrado de cada `id` presente — só ids dinâmicos têm
  /// halo, pela mesma razão. [haloSigmaScale] é o controle do usuário sobre
  /// a largura do halo (ver [ScenePainter.paintHalo]).
  void paint(
    ui.Canvas canvas,
    Map<String, ui.Color> colorOverrides, {
    Map<String, ui.Color> haloColors = const {},
    double haloSigmaScale = 1.0,
  }) {
    if (_disposed) {
      return;
    }
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      switch (segment) {
        case StaticSegment():
          canvas.drawPicture(_pictureAt(i));
        case DynamicSegment():
          for (final item in segment.items) {
            final transform = item.transform;
            if (transform != null) {
              canvas.save();
              canvas.transform(transform.toMatrix4());
            }
            final id = item.node.id;
            final halo = id == null ? null : haloColors[id];
            if (halo != null) {
              _painter.paintHalo(
                canvas,
                item.node,
                item.inheritedColor,
                halo,
                sigmaScale: haloSigmaScale,
              );
            }
            _painter.paintSubtree(
              canvas,
              item.node,
              item.inheritedColor,
              overrides: colorOverrides,
            );
            if (transform != null) {
              canvas.restore();
            }
          }
      }
    }
  }

  /// Aplica a transformação de página (§3) ao [canvas].
  void applyPageTransform(ui.Canvas canvas) =>
      _painter.applyPageTransform(canvas);

  /// Descarta os `Picture` gravados. Idempotente. Sem isto o cache vaza
  /// memória nativa que o GC do Dart não cobra.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (var i = 0; i < _pictures.length; i++) {
      final picture = _pictures[i];
      if (picture != null) {
        picture.dispose();
        _pictures[i] = null;
        stats.disposals++;
      }
    }
  }

  @visibleForTesting
  int get compiledCount => _pictures.where((p) => p != null).length;
}
