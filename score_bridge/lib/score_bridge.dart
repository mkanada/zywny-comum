/// Modelo e parser do formato `.vsb` (Verovio Score Bridge).
///
/// Ver docs/formato/especificacao-v1.md na raiz do repositório.
library;

export 'src/model.dart';
export 'src/expansion.dart';
export 'src/geometry.dart';
export 'src/dash.dart';
export 'src/glyph_cache.dart';
export 'src/scene_painter.dart';
export 'src/scene_walk.dart' show SceneVisitor, walkScene;
export 'src/highlight_engine.dart';
export 'src/hit_test.dart';
export 'src/page_layers.dart' show PageLayers, PictureStats;
export 'src/score_controller.dart';
export 'src/score_cursor.dart';
export 'src/score_page_view.dart';
export 'src/score_player.dart';
export 'src/score_view.dart';
export 'src/segmentation.dart';
export 'src/text_font.dart';
export 'src/text_run.dart';
export 'src/parser.dart'
    show
        parseManifestDocument,
        parseMetaDocument,
        parseGlyphsDocument,
        parseSceneDocument,
        parseTimemapDocument,
        parseAlternatesDocument,
        parseMidiDocument;
