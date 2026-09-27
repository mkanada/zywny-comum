// Parser do formato `.vsb` (Verovio Score Bridge).
//
// Aceita tanto o pacote zip (`-t vsb`) quanto o JSON único (`-t vsb-json`,
// docs/formato/especificacao-v1.md §2.2), além dos documentos individuais
// (`scene.json`, `glyphs.json`, `manifest.json`, `timemap.json`) via as
// funções `parseXxxDocument`.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:archive/archive.dart';

import 'model.dart';

const int _supportedFormatVersion = 1;

/// Implementação de [VsbDocument.fromBytes].
VsbDocument parseVsbDocumentBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    return _fromZipBytes(bytes);
  }
  final decoded = json.decode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic>) {
    throw const VsbFormatException('', 'documento raiz deve ser um objeto');
  }
  return _fromDocumentJson(decoded);
}

/// Implementação de [VsbDocument.fromJson].
VsbDocument parseVsbDocumentJson(Map<String, dynamic> json) =>
    _fromDocumentJson(json);

VsbDocument _fromZipBytes(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  Map<String, dynamic> readJsonEntry(String name, {bool required = true}) {
    final entry = archive.findFile(name);
    if (entry == null) {
      if (required) {
        throw VsbFormatException('', 'pacote .vsb sem "$name"');
      }
      return const {};
    }
    final bytes = entry.readBytes();
    if (bytes == null) {
      throw VsbFormatException('', 'não foi possível ler "$name" do pacote');
    }
    final decoded = json.decode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw VsbFormatException(name, 'esperado objeto JSON em "$name"');
    }
    return decoded;
  }

  final manifestJson = readJsonEntry('manifest.json');
  final manifest = parseManifestDocument(manifestJson, path: 'manifest');
  _checkVersion(manifest.version);

  final glyphsJson = readJsonEntry('glyphs.json');
  final glyphs = parseGlyphsDocument(glyphsJson, path: 'glyphs');

  final sceneEntry = archive.findFile('scene.json');
  if (sceneEntry == null) {
    throw const VsbFormatException('', 'pacote .vsb sem "scene.json"');
  }
  final sceneBytes = sceneEntry.readBytes()!;
  final sceneDecoded = json.decode(utf8.decode(sceneBytes));
  if (sceneDecoded is! Map<String, dynamic>) {
    throw const VsbFormatException(
      'scene',
      'esperado objeto JSON em "scene.json"',
    );
  }
  final pages = parseSceneDocument(sceneDecoded, path: 'scene');

  List<TimemapEntry>? timemap;
  if (manifest.files.timemap != null) {
    final timemapEntry = archive.findFile(manifest.files.timemap!);
    if (timemapEntry != null) {
      final timemapBytes = timemapEntry.readBytes()!;
      final timemapDecoded = json.decode(utf8.decode(timemapBytes));
      timemap = parseTimemapDocument(timemapDecoded, path: 'timemap');
    }
  }

  VsbMeta? meta;
  if (manifest.files.meta != null) {
    final metaEntry = archive.findFile(manifest.files.meta!);
    if (metaEntry != null) {
      final metaDecoded = json.decode(utf8.decode(metaEntry.readBytes()!));
      meta = parseMetaDocument(metaDecoded, path: 'meta');
    }
  }

  VsbMidi? midi;
  if (manifest.files.midi != null) {
    final midiEntry = archive.findFile(manifest.files.midi!);
    if (midiEntry != null) {
      final midiDecoded = json.decode(utf8.decode(midiEntry.readBytes()!));
      midi = parseMidiDocument(midiDecoded, path: 'midi');
    }
  }

  // Parse preguiçoso (VsbDocument.alternates): o zip já trouxe todos os bytes
  // para a memória (ZipDecoder.decodeBytes), então só adiamos o json.decode e
  // a montagem da árvore de página em si — o que mediu 4,6x mais lento na
  // Maple Leaf Rag (VsbDocument.alternates, notas de P03a).
  final alternatesFileName = manifest.files.alternates;
  List<AlternateSequence> loadAlternates() {
    if (alternatesFileName == null) return const [];
    final alternatesEntry = archive.findFile(alternatesFileName);
    if (alternatesEntry == null) return const [];
    final alternatesDecoded = json.decode(
      utf8.decode(alternatesEntry.readBytes()!),
    );
    return parseAlternatesDocument(
      _asMap(alternatesDecoded, 'alternates'),
      path: 'alternates',
    );
  }

  return VsbDocument(
    manifest: manifest,
    glyphs: glyphs,
    pages: pages,
    timemap: timemap,
    meta: meta,
    midi: midi,
    alternatesLoader: loadAlternates,
  );
}

VsbDocument _fromDocumentJson(Map<String, dynamic> root) {
  final manifestJson = _requireMap(root, 'manifest', 'manifest');
  final manifest = parseManifestDocument(manifestJson, path: 'manifest');
  _checkVersion(manifest.version);

  final glyphsJson = _requireMap(root, 'glyphs', 'glyphs');
  final glyphs = parseGlyphsDocument(glyphsJson, path: 'glyphs');

  final sceneJson = _requireMap(root, 'scene', 'scene');
  final pages = parseSceneDocument(sceneJson, path: 'scene');

  List<TimemapEntry>? timemap;
  if (root.containsKey('timemap') && root['timemap'] != null) {
    timemap = parseTimemapDocument(root['timemap'], path: 'timemap');
  }

  VsbMeta? meta;
  if (root.containsKey('meta') && root['meta'] != null) {
    meta = parseMetaDocument(root['meta'], path: 'meta');
  }

  VsbMidi? midi;
  if (root.containsKey('midi') && root['midi'] != null) {
    midi = parseMidiDocument(root['midi'], path: 'midi');
  }

  // Parse preguiçoso (VsbDocument.alternates): o JSON já está todo decodificado
  // em memória aqui (era um `Map` só); o que adiamos é a montagem da árvore de
  // página (ver a mesma nota em _fromZipBytes).
  final alternatesJson = root['alternates'];
  List<AlternateSequence> loadAlternates() {
    if (alternatesJson == null) return const [];
    return parseAlternatesDocument(
      _asMap(alternatesJson, 'alternates'),
      path: 'alternates',
    );
  }

  return VsbDocument(
    manifest: manifest,
    glyphs: glyphs,
    pages: pages,
    timemap: timemap,
    meta: meta,
    midi: midi,
    alternatesLoader: loadAlternates,
  );
}

void _checkVersion(int version) {
  if (version != _supportedFormatVersion) {
    throw UnsupportedVsbVersionException(version);
  }
}

// ---------------------------------------------------------------------------
// manifest.json (§2.1)
// ---------------------------------------------------------------------------

VsbManifest parseManifestDocument(
  Map<String, dynamic> json, {
  required String path,
}) {
  final format = _asString(_requireField(json, 'format', path), '$path.format');
  final version = _asInt(_requireField(json, 'version', path), '$path.version');
  final generator = _asString(
    _requireField(json, 'generator', path),
    '$path.generator',
  );
  final pageCount = _asInt(
    _requireField(json, 'pageCount', path),
    '$path.pageCount',
  );
  final filesJson = _requireMap(json, 'files', path, fieldPath: '$path.files');
  final files = VsbManifestFiles(
    scene: _asString(
      _requireField(filesJson, 'scene', '$path.files'),
      '$path.files.scene',
    ),
    glyphs: _asString(
      _requireField(filesJson, 'glyphs', '$path.files'),
      '$path.files.glyphs',
    ),
    timemap: filesJson['timemap'] == null
        ? null
        : _asString(filesJson['timemap'], '$path.files.timemap'),
    meta: filesJson['meta'] == null
        ? null
        : _asString(filesJson['meta'], '$path.files.meta'),
    alternates: filesJson['alternates'] == null
        ? null
        : _asString(filesJson['alternates'], '$path.files.alternates'),
    midi: filesJson['midi'] == null
        ? null
        : _asString(filesJson['midi'], '$path.files.midi'),
  );
  return VsbManifest(
    format: format,
    version: version,
    generator: generator,
    pageCount: pageCount,
    files: files,
  );
}

// ---------------------------------------------------------------------------
// glyphs.json (§4)
// ---------------------------------------------------------------------------

Map<String, GlyphDef> parseGlyphsDocument(
  Map<String, dynamic> json, {
  required String path,
}) {
  final result = <String, GlyphDef>{};
  for (final entry in json.entries) {
    final glyphPath = '$path[${entry.key}]';
    final glyphJson = entry.value;
    if (glyphJson is! Map<String, dynamic>) {
      throw VsbFormatException(
        glyphPath,
        'esperado objeto de definição de glifo',
      );
    }
    result[entry.key] = _parseGlyphDef(glyphJson, glyphPath);
  }
  return result;
}

GlyphDef _parseGlyphDef(Map<String, dynamic> json, String path) {
  final pathsJson = _requireList(json, 'paths', path, fieldPath: '$path.paths');
  final paths = <BezierPath>[
    for (var k = 0; k < pathsJson.length; k++)
      _parseBezier(_asMap(pathsJson[k], '$path.paths[$k]'), '$path.paths[$k]'),
  ];
  return GlyphDef(
    font: _asString(_requireField(json, 'font', path), '$path.font'),
    codepoint: _asString(
      _requireField(json, 'codepoint', path),
      '$path.codepoint',
    ),
    unitsPerEm: _asInt(
      _requireField(json, 'unitsPerEm', path),
      '$path.unitsPerEm',
    ),
    horizAdvX: _asDouble(
      _requireField(json, 'horizAdvX', path),
      '$path.horizAdvX',
    ),
    bbox: _parseGlyphBBox(_requireField(json, 'bbox', path), '$path.bbox'),
    paths: paths,
  );
}

BezierPath _parseBezier(Map<String, dynamic> json, String path) {
  final closed = _asBool(_requireField(json, 'closed', path), '$path.closed');
  final v = _asFlatNumbers(_requireField(json, 'v', path), '$path.v');
  final i = _asFlatNumbers(_requireField(json, 'i', path), '$path.i');
  final o = _asFlatNumbers(_requireField(json, 'o', path), '$path.o');
  if (v.length.isOdd) {
    throw VsbFormatException(
      '$path.v',
      'comprimento de "v" deve ser par, recebido ${v.length}',
    );
  }
  if (i.length.isOdd) {
    throw VsbFormatException(
      '$path.i',
      'comprimento de "i" deve ser par, recebido ${i.length}',
    );
  }
  if (o.length.isOdd) {
    throw VsbFormatException(
      '$path.o',
      'comprimento de "o" deve ser par, recebido ${o.length}',
    );
  }
  if (v.length != i.length || v.length != o.length) {
    throw VsbFormatException(
      path,
      'v/i/o devem ter o mesmo comprimento (v=${v.length}, i=${i.length}, o=${o.length})',
    );
  }
  return BezierPath(closed: closed, v: v, i: i, o: o);
}

// ---------------------------------------------------------------------------
// meta.json (§2.3)
// ---------------------------------------------------------------------------

VsbMeta parseMetaDocument(dynamic json, {required String path}) {
  final map = _asMap(json, path);
  final creatorsJson = map['creators'];
  if (creatorsJson != null && creatorsJson is! List) {
    throw VsbFormatException('$path.creators', 'esperado array de créditos');
  }
  return VsbMeta(
    title: map['title'] == null ? null : _asString(map['title'], '$path.title'),
    creators: [
      if (creatorsJson != null)
        for (var k = 0; k < (creatorsJson as List).length; k++)
          _parseCreator(
            _asMap(creatorsJson[k], '$path.creators[$k]'),
            '$path.creators[$k]',
          ),
    ],
  );
}

VsbCreator _parseCreator(Map<String, dynamic> json, String path) {
  return VsbCreator(
    name: _asString(_requireField(json, 'name', path), '$path.name'),
    role: json['role'] == null ? null : _asString(json['role'], '$path.role'),
  );
}

// ---------------------------------------------------------------------------
// midi.json (§2.7)
// ---------------------------------------------------------------------------

VsbMidi parseMidiDocument(dynamic json, {required String path}) {
  final map = _asMap(json, path);
  final notesJson = _requireList(map, 'notes', path, fieldPath: '$path.notes');
  final pedalJson = _requireList(map, 'pedal', path, fieldPath: '$path.pedal');
  return VsbMidi(
    notes: [
      for (var k = 0; k < notesJson.length; k++)
        _parseMidiNote(
          _asMap(notesJson[k], '$path.notes[$k]'),
          '$path.notes[$k]',
        ),
    ],
    pedal: [
      for (var k = 0; k < pedalJson.length; k++)
        _parseMidiPedal(
          _asMap(pedalJson[k], '$path.pedal[$k]'),
          '$path.pedal[$k]',
        ),
    ],
  );
}

MidiNote _parseMidiNote(Map<String, dynamic> json, String path) {
  final tiedJson = json['tied'];
  if (tiedJson != null && tiedJson is! List) {
    throw VsbFormatException('$path.tied', 'esperado array de ids');
  }
  return MidiNote(
    id: _asString(_requireField(json, 'id', path), '$path.id'),
    onMs: _asDouble(_requireField(json, 'on', path), '$path.on'),
    offMs: _asDouble(_requireField(json, 'off', path), '$path.off'),
    pitch: _asInt(_requireField(json, 'p', path), '$path.p'),
    staff: _asInt(_requireField(json, 's', path), '$path.s'),
    layer: _asInt(_requireField(json, 'l', path), '$path.l'),
    channel: json['c'] == null ? 0 : _asInt(json['c'], '$path.c'),
    program: json['pg'] == null ? 0 : _asInt(json['pg'], '$path.pg'),
    velocity: _asInt(_requireField(json, 'v', path), '$path.v'),
    tied: tiedJson == null ? const [] : _asStringList(tiedJson, '$path.tied'),
    ornament: json['orn'] == null ? false : _asBool(json['orn'], '$path.orn'),
  );
}

MidiPedal _parseMidiPedal(Map<String, dynamic> json, String path) {
  return MidiPedal(
    id: _asString(_requireField(json, 'id', path), '$path.id'),
    timeMs: _asDouble(_requireField(json, 't', path), '$path.t'),
    dir: _asPedalDir(_requireField(json, 'dir', path), '$path.dir'),
    staff: _asInt(_requireField(json, 's', path), '$path.s'),
    channel: json['c'] == null ? 0 : _asInt(json['c'], '$path.c'),
  );
}

PedalDir _asPedalDir(dynamic value, String path) {
  final s = _asString(value, path);
  switch (s) {
    case 'down':
      return PedalDir.down;
    case 'up':
      return PedalDir.up;
    default:
      throw VsbFormatException(path, 'dir de pedal desconhecido: "$s"');
  }
}

// ---------------------------------------------------------------------------
// scene.json (§5)
// ---------------------------------------------------------------------------

List<ScenePage> parseSceneDocument(
  Map<String, dynamic> json, {
  required String path,
}) {
  final pagesJson = _requireList(json, 'pages', path, fieldPath: '$path.pages');
  return [
    for (var k = 0; k < pagesJson.length; k++)
      _parseScenePage(
        _asMap(pagesJson[k], '$path.pages[$k]'),
        '$path.pages[$k]',
      ),
  ];
}

ScenePage _parseScenePage(Map<String, dynamic> json, String path) {
  final fitJson = _requireMap(json, 'fit', path, fieldPath: '$path.fit');
  final fit = PageFit(
    scale: _asDouble(
      _requireField(fitJson, 'scale', '$path.fit'),
      '$path.fit.scale',
    ),
    tx: _asDouble(_requireField(fitJson, 'tx', '$path.fit'), '$path.fit.tx'),
    ty: _asDouble(_requireField(fitJson, 'ty', '$path.fit'), '$path.fit.ty'),
  );

  final rootJson = _requireMap(json, 'root', path, fieldPath: '$path.root');
  // `elements` não vem do JSON: é derivado desta mesma passada (§5.5).
  final index = _PageIndex();
  final root = _parseNode(rootJson, '$path.root', index);

  return ScenePage(
    index: _asInt(_requireField(json, 'index', path), '$path.index'),
    width: _asInt(_requireField(json, 'width', path), '$path.width'),
    height: _asInt(_requireField(json, 'height', path), '$path.height'),
    contentHeight: _asInt(
      _requireField(json, 'contentHeight', path),
      '$path.contentHeight',
    ),
    viewBoxFactor: _asDouble(
      _requireField(json, 'viewBoxFactor', path),
      '$path.viewBoxFactor',
    ),
    viewBox: _asRect(_requireField(json, 'viewBox', path), '$path.viewBox'),
    baseWidth: _asInt(
      _requireField(json, 'baseWidth', path),
      '$path.baseWidth',
    ),
    baseHeight: _asInt(
      _requireField(json, 'baseHeight', path),
      '$path.baseHeight',
    ),
    userScaleX: _asDouble(
      _requireField(json, 'userScaleX', path),
      '$path.userScaleX',
    ),
    userScaleY: _asDouble(
      _requireField(json, 'userScaleY', path),
      '$path.userScaleY',
    ),
    widthPx: _asInt(_requireField(json, 'widthPx', path), '$path.widthPx'),
    heightPx: _asInt(_requireField(json, 'heightPx', path), '$path.heightPx'),
    fit: fit,
    origin: _asOffset(_requireField(json, 'origin', path), '$path.origin'),
    root: root,
    elements: index.elements,
    byId: index.byId,
  );
}

/// Acumuladores derivados do percurso da árvore de uma página: o mapa
/// `xml:id` → nó e o índice plano de §5.5, que o formato não carrega.
///
/// `nodePath` é a posição em pré-ordem contando **só nós de grupo** (a raiz é
/// 0), como manda §5.5; por isso o contador avança em [_parseNode] e a entrada
/// é anexada antes dos filhos, o que mantém [elements] em pré-ordem.
class _PageIndex {
  final Map<String, SceneNode> byId = <String, SceneNode>{};
  final List<IndexEntry> elements = <IndexEntry>[];
  int nodePath = -1;
}

SceneNode _parseNode(Map<String, dynamic> json, String path, _PageIndex index) {
  final id = json['id'] == null ? null : _asString(json['id'], '$path.id');
  final className = json['class'] == null
      ? ''
      : _asString(json['class'], '$path.class');
  final color = json['color'] == null
      ? null
      : _asString(json['color'], '$path.color');
  final hidden = json['hidden'] == null
      ? false
      : _asBool(json['hidden'], '$path.hidden');
  final rotate = json['rotate'] == null
      ? null
      : _parseRotate(_asMap(json['rotate'], '$path.rotate'), '$path.rotate');
  final bbox = json['bbox'] == null
      ? null
      : _asRect(json['bbox'], '$path.bbox');

  // Antes dos filhos: mantém [_PageIndex.elements] em pré-ordem. Um nó com
  // `id` mas sem bbox (milestone, grupo vazio) indexa `Rect.zero`, que é o
  // `[0, 0, 0, 0]` que o formato gravava (§5.5).
  final nodePath = ++index.nodePath;
  if (id != null) {
    index.elements.add(
      IndexEntry(
        id: id,
        className: className,
        nodePath: nodePath,
        bbox: bbox ?? Rect.zero,
      ),
    );
  }

  final childrenJson = json['children'];
  if (childrenJson is! List) {
    throw VsbFormatException(
      '$path.children',
      'campo obrigatório "children" ausente ou inválido',
    );
  }
  final children = <SceneChild>[
    for (var k = 0; k < childrenJson.length; k++)
      _parseChild(
        _asMap(childrenJson[k], '$path.children[$k]'),
        '$path.children[$k]',
        index,
      ),
  ];

  final node = SceneNode(
    id: id,
    className: className,
    color: color,
    hidden: hidden,
    rotate: rotate,
    bbox: bbox,
    children: children,
  );
  if (id != null) {
    index.byId[id] = node;
  }
  return node;
}

SceneRotate _parseRotate(Map<String, dynamic> json, String path) {
  return SceneRotate(
    angle: _asDouble(_requireField(json, 'angle', path), '$path.angle'),
    origin: _asOffset(_requireField(json, 'origin', path), '$path.origin'),
  );
}

SceneChild _parseChild(
  Map<String, dynamic> json,
  String path,
  _PageIndex index,
) {
  final t = _asString(_requireField(json, 't', path), '$path.t');
  switch (t) {
    case 'g':
      return _parseNode(json, path, index);
    case 'p':
      return _parseScenePath(json, path);
    case 'r':
      return _parseSceneRect(json, path);
    case 'e':
      return _parseSceneEllipse(json, path);
    case 'u':
      return _parseSceneGlyphUse(json, path);
    case 't':
      return _parseSceneText(json, path);
    default:
      throw VsbFormatException(
        '$path.t',
        'tipo de elemento desconhecido: "$t"',
      );
  }
}

ScenePath _parseScenePath(Map<String, dynamic> json, String path) {
  final pathsJson = _requireList(json, 'paths', path, fieldPath: '$path.paths');
  final paths = <BezierPath>[
    for (var k = 0; k < pathsJson.length; k++)
      _parseBezier(_asMap(pathsJson[k], '$path.paths[$k]'), '$path.paths[$k]'),
  ];
  final style = _parseShapeStyle(json, path);
  return ScenePath(
    paths: paths,
    fill: style.fill,
    fillOpacity: style.fillOpacity,
    stroke: style.stroke,
    strokeWidth: style.strokeWidth,
    strokeOpacity: style.strokeOpacity,
    lineCap: style.lineCap,
    lineJoin: style.lineJoin,
    dash: style.dash,
  );
}

SceneRect _parseSceneRect(Map<String, dynamic> json, String path) {
  final style = _parseShapeStyle(json, path);
  return SceneRect(
    x: _asDouble(_requireField(json, 'x', path), '$path.x'),
    y: _asDouble(_requireField(json, 'y', path), '$path.y'),
    w: _asDouble(_requireField(json, 'w', path), '$path.w'),
    h: _asDouble(_requireField(json, 'h', path), '$path.h'),
    rx: json['rx'] == null ? 0.0 : _asDouble(json['rx'], '$path.rx'),
    fill: style.fill,
    fillOpacity: style.fillOpacity,
    stroke: style.stroke,
    strokeWidth: style.strokeWidth,
    strokeOpacity: style.strokeOpacity,
    lineCap: style.lineCap,
    lineJoin: style.lineJoin,
    dash: style.dash,
  );
}

SceneEllipse _parseSceneEllipse(Map<String, dynamic> json, String path) {
  final style = _parseShapeStyle(json, path);
  return SceneEllipse(
    cx: _asDouble(_requireField(json, 'cx', path), '$path.cx'),
    cy: _asDouble(_requireField(json, 'cy', path), '$path.cy'),
    rx: _asDouble(_requireField(json, 'rx', path), '$path.rx'),
    ry: _asDouble(_requireField(json, 'ry', path), '$path.ry'),
    fill: style.fill,
    fillOpacity: style.fillOpacity,
    stroke: style.stroke,
    strokeWidth: style.strokeWidth,
    strokeOpacity: style.strokeOpacity,
    lineCap: style.lineCap,
    lineJoin: style.lineJoin,
    dash: style.dash,
  );
}

SceneGlyphUse _parseSceneGlyphUse(Map<String, dynamic> json, String path) {
  final style = _parseShapeStyle(json, path);
  return SceneGlyphUse(
    glyphId: _asString(_requireField(json, 'g', path), '$path.g'),
    x: _asDouble(_requireField(json, 'x', path), '$path.x'),
    y: _asDouble(_requireField(json, 'y', path), '$path.y'),
    sx: _asDouble(_requireField(json, 'sx', path), '$path.sx'),
    sy: _asDouble(_requireField(json, 'sy', path), '$path.sy'),
    fill: style.fill,
    fillOpacity: style.fillOpacity,
    stroke: style.stroke,
    strokeWidth: style.strokeWidth,
    strokeOpacity: style.strokeOpacity,
    lineCap: style.lineCap,
    lineJoin: style.lineJoin,
    dash: style.dash,
  );
}

SceneText _parseSceneText(Map<String, dynamic> json, String path) {
  return SceneText(
    text: _asString(_requireField(json, 's', path), '$path.s'),
    x: _asDouble(_requireField(json, 'x', path), '$path.x'),
    y: _asDouble(_requireField(json, 'y', path), '$path.y'),
    size: _asDouble(_requireField(json, 'size', path), '$path.size'),
    align: _asTextAlign(_requireField(json, 'align', path), '$path.align'),
    letterSpacing: json['letterSpacing'] == null
        ? 0.0
        : _asDouble(json['letterSpacing'], '$path.letterSpacing'),
    bold: json['bold'] == null ? false : _asBool(json['bold'], '$path.bold'),
    italic: json['italic'] == null
        ? false
        : _asBool(json['italic'], '$path.italic'),
    family: _asString(_requireField(json, 'family', path), '$path.family'),
    color: json['color'] == null
        ? null
        : _asString(json['color'], '$path.color'),
  );
}

class _ShapeStyle {
  final ScenePaint fill;
  final double fillOpacity;
  final ScenePaint stroke;
  final double? strokeWidth;
  final double strokeOpacity;
  final SceneLineCap lineCap;
  final SceneLineJoin lineJoin;
  final SceneDash? dash;

  const _ShapeStyle({
    required this.fill,
    required this.fillOpacity,
    required this.stroke,
    required this.strokeWidth,
    required this.strokeOpacity,
    required this.lineCap,
    required this.lineJoin,
    required this.dash,
  });
}

_ShapeStyle _parseShapeStyle(Map<String, dynamic> json, String path) {
  return _ShapeStyle(
    fill: _asPaint(json['fill'], '$path.fill'),
    fillOpacity: json['fillOpacity'] == null
        ? 1.0
        : _asDouble(json['fillOpacity'], '$path.fillOpacity'),
    stroke: _asPaint(json['stroke'], '$path.stroke'),
    strokeWidth: json['strokeWidth'] == null
        ? null
        : _asDouble(json['strokeWidth'], '$path.strokeWidth'),
    strokeOpacity: json['strokeOpacity'] == null
        ? 1.0
        : _asDouble(json['strokeOpacity'], '$path.strokeOpacity'),
    lineCap: json['lineCap'] == null
        ? SceneLineCap.defaultCap
        : _asLineCap(json['lineCap'], '$path.lineCap'),
    lineJoin: json['lineJoin'] == null
        ? SceneLineJoin.defaultJoin
        : _asLineJoin(json['lineJoin'], '$path.lineJoin'),
    dash: json['dash'] == null ? null : _asDash(json['dash'], '$path.dash'),
  );
}

// ---------------------------------------------------------------------------
// alternates.json (§2.5)
// ---------------------------------------------------------------------------

List<AlternateSequence> parseAlternatesDocument(
  Map<String, dynamic> json, {
  required String path,
}) {
  final sequencesJson = _requireList(
    json,
    'sequences',
    path,
    fieldPath: '$path.sequences',
  );
  return [
    for (var k = 0; k < sequencesJson.length; k++)
      _parseAlternateSequence(
        _asMap(sequencesJson[k], '$path.sequences[$k]'),
        '$path.sequences[$k]',
      ),
  ];
}

AlternateSequence _parseAlternateSequence(
  Map<String, dynamic> json,
  String path,
) {
  final start = _asString(_requireField(json, 'start', path), '$path.start');
  // Mesmo `_parseScenePage` de scene.json (§5): uma página de sequência tem
  // exatamente a mesma forma de uma página normal (§2.5).
  final pagesJson = _requireList(json, 'pages', path, fieldPath: '$path.pages');
  final pages = <ScenePage>[
    for (var k = 0; k < pagesJson.length; k++)
      _parseScenePage(
        _asMap(pagesJson[k], '$path.pages[$k]'),
        '$path.pages[$k]',
      ),
  ];
  return AlternateSequence(start: start, pages: pages);
}

// ---------------------------------------------------------------------------
// timemap.json
// ---------------------------------------------------------------------------

List<TimemapEntry> parseTimemapDocument(dynamic json, {required String path}) {
  if (json is! List) {
    throw VsbFormatException(path, 'esperado array de instantes de timemap');
  }
  return [
    for (var k = 0; k < json.length; k++)
      _parseTimemapEntry(_asMap(json[k], '$path[$k]'), '$path[$k]'),
  ];
}

TimemapEntry _parseTimemapEntry(Map<String, dynamic> json, String path) {
  return TimemapEntry(
    qstamp: json['qstamp'] == null
        ? null
        : _asDouble(json['qstamp'], '$path.qstamp'),
    qfrac: json['qfrac'] == null
        ? null
        : _asIntList(json['qfrac'], '$path.qfrac'),
    tstamp: _asDouble(_requireField(json, 'tstamp', path), '$path.tstamp'),
    on: json['on'] == null ? const [] : _asStringList(json['on'], '$path.on'),
    off: json['off'] == null
        ? const []
        : _asStringList(json['off'], '$path.off'),
    restsOn: json['restsOn'] == null
        ? const []
        : _asStringList(json['restsOn'], '$path.restsOn'),
    restsOff: json['restsOff'] == null
        ? const []
        : _asStringList(json['restsOff'], '$path.restsOff'),
    tempo: json['tempo'] == null
        ? null
        : _asDouble(json['tempo'], '$path.tempo'),
    measureOn: json['measureOn'] == null
        ? null
        : _asString(json['measureOn'], '$path.measureOn'),
  );
}

// ---------------------------------------------------------------------------
// Helpers de acesso/validação de JSON.
// ---------------------------------------------------------------------------

dynamic _requireField(
  Map<String, dynamic> json,
  String key,
  String parentPath,
) {
  if (!json.containsKey(key) || json[key] == null) {
    throw VsbFormatException(
      parentPath.isEmpty ? key : '$parentPath.$key',
      'campo obrigatório "$key" ausente',
    );
  }
  return json[key];
}

Map<String, dynamic> _requireMap(
  Map<String, dynamic> json,
  String key,
  String parentPath, {
  String? fieldPath,
}) {
  final value = _requireField(json, key, parentPath);
  return _asMap(
    value,
    fieldPath ?? (parentPath.isEmpty ? key : '$parentPath.$key'),
  );
}

List<dynamic> _requireList(
  Map<String, dynamic> json,
  String key,
  String parentPath, {
  String? fieldPath,
}) {
  final value = _requireField(json, key, parentPath);
  final path = fieldPath ?? (parentPath.isEmpty ? key : '$parentPath.$key');
  if (value is! List) {
    throw VsbFormatException(
      path,
      'esperado array, recebido ${value.runtimeType}',
    );
  }
  return value;
}

Map<String, dynamic> _asMap(dynamic value, String path) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw VsbFormatException(
    path,
    'esperado objeto, recebido ${value.runtimeType}',
  );
}

double _asDouble(dynamic value, String path) {
  if (value is num) return value.toDouble();
  throw VsbFormatException(
    path,
    'esperado número, recebido ${value.runtimeType}',
  );
}

int _asInt(dynamic value, String path) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw VsbFormatException(
    path,
    'esperado inteiro, recebido ${value.runtimeType}',
  );
}

bool _asBool(dynamic value, String path) {
  if (value is bool) return value;
  throw VsbFormatException(
    path,
    'esperado booleano, recebido ${value.runtimeType}',
  );
}

String _asString(dynamic value, String path) {
  if (value is String) return value;
  throw VsbFormatException(
    path,
    'esperado string, recebido ${value.runtimeType}',
  );
}

List<String> _asStringList(dynamic value, String path) {
  if (value is! List) {
    throw VsbFormatException(path, 'esperado array de strings');
  }
  return [
    for (var k = 0; k < value.length; k++) _asString(value[k], '$path[$k]'),
  ];
}

List<int> _asIntList(dynamic value, String path) {
  if (value is! List) {
    throw VsbFormatException(path, 'esperado array de inteiros');
  }
  return [for (var k = 0; k < value.length; k++) _asInt(value[k], '$path[$k]')];
}

Float64List _asFlatNumbers(dynamic value, String path) {
  if (value is! List) {
    throw VsbFormatException(path, 'esperado array de números');
  }
  final result = Float64List(value.length);
  for (var k = 0; k < value.length; k++) {
    final item = value[k];
    if (item is! num) {
      throw VsbFormatException(
        '$path[$k]',
        'esperado número, recebido ${item.runtimeType}',
      );
    }
    result[k] = item.toDouble();
  }
  return result;
}

Rect _asRect(dynamic value, String path) {
  if (value is! List || value.length != 4) {
    throw VsbFormatException(
      path,
      'esperado array de 4 números [x0, y0, x1, y1]',
    );
  }
  final n = _asFlatNumbers(value, path);
  return Rect.fromLTRB(n[0], n[1], n[2], n[3]);
}

GlyphBBox _parseGlyphBBox(dynamic value, String path) {
  if (value is! List || value.length != 4) {
    throw VsbFormatException(
      path,
      'esperado array de 4 números [x, y, width, height]',
    );
  }
  final n = _asFlatNumbers(value, path);
  return GlyphBBox(x: n[0], y: n[1], width: n[2], height: n[3]);
}

Offset _asOffset(dynamic value, String path) {
  if (value is! List || value.length != 2) {
    throw VsbFormatException(path, 'esperado array de 2 números [x, y]');
  }
  final n = _asFlatNumbers(value, path);
  return Offset(n[0], n[1]);
}

ScenePaint _asPaint(dynamic value, String path) {
  if (value == null) return ScenePaint.inherit;
  if (value == 'none') return ScenePaint.none;
  if (value is String) return ColorPaint(value);
  throw VsbFormatException(
    path,
    'esperado "none" ou cor hex, recebido ${value.runtimeType}',
  );
}

SceneLineCap _asLineCap(dynamic value, String path) {
  final s = _asString(value, path);
  switch (s) {
    case 'default':
      return SceneLineCap.defaultCap;
    case 'butt':
      return SceneLineCap.butt;
    case 'round':
      return SceneLineCap.round;
    case 'square':
      return SceneLineCap.square;
    default:
      throw VsbFormatException(path, 'lineCap desconhecido: "$s"');
  }
}

SceneLineJoin _asLineJoin(dynamic value, String path) {
  final s = _asString(value, path);
  switch (s) {
    case 'default':
      return SceneLineJoin.defaultJoin;
    case 'arcs':
      return SceneLineJoin.arcs;
    case 'bevel':
      return SceneLineJoin.bevel;
    case 'miter':
      return SceneLineJoin.miter;
    case 'miter-clip':
      return SceneLineJoin.miterClip;
    case 'round':
      return SceneLineJoin.round;
    default:
      throw VsbFormatException(path, 'lineJoin desconhecido: "$s"');
  }
}

SceneDash _asDash(dynamic value, String path) {
  if (value is! List || value.length != 2) {
    throw VsbFormatException(
      path,
      'esperado array de 2 números [dashLength, gapLength]',
    );
  }
  final n = _asFlatNumbers(value, path);
  return SceneDash(n[0], n[1]);
}

SceneTextAlign _asTextAlign(dynamic value, String path) {
  final s = _asString(value, path);
  switch (s) {
    case 'left':
      return SceneTextAlign.left;
    case 'center':
      return SceneTextAlign.center;
    case 'right':
      return SceneTextAlign.right;
    default:
      throw VsbFormatException(path, 'align desconhecido: "$s"');
  }
}
