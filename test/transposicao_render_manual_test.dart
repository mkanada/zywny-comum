// Q01: o Verovio transpondo pelo caminho do app (`renderScoreToVsb` com a opção
// `transpose` em `VsbRenderRequest.options`), em hinos reais do Hymn_Grabber:
// notas, tempos e armadura conferidos, tempo de render e a leitura das
// armaduras compasso a compasso (o aviso "a partir do compasso N…").
//
//   Q01_TRANSPOSE=1 flutter test test/transposicao_render_manual_test.dart
//
// A medição do catálogo inteiro é `tool/medir_transposicao.py` (CLI do fork);
// este teste confere que o caminho do app dá o mesmo e mede o que o CLI não
// mede. Os números vão para docs/plano/Q01-verovio-transpondo.md.
@Tags(['manual'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_bridge/score_bridge.dart';

import 'support/render_helper.dart';

/// Hino, armadura (quintas) e o intervalo da tabela do Q00.
const _hinos = [
  (numero: '013', fifths: -3, intervalo: '-m3', k: -3), // 3♭, 316 notas -rend
  (numero: '001', fifths: 2, intervalo: '-M2', k: -2), // 2♯
  (
    numero: '367',
    fifths: -2,
    intervalo: 'M2',
    k: 2,
  ), // 4 sequências alternativas
  (numero: '031', fifths: 1, intervalo: 'P4', k: 5), // muda de armadura no meio
];

final _rend = RegExp(r'-rend\d+$');

File _musicxml(String numero) {
  for (final pasta in ['musicxml_special', 'musicxml']) {
    final file = File('$kHymnGrabber/$pasta/$numero.musicxml');
    if (file.existsSync()) return file;
  }
  throw StateError('sem o hino $numero em $kHymnGrabber');
}

/// Armadura vigente (quintas) de um `key` do pitchpos; `null` se não é uma
/// das 15 padronizadas.
int? _quintas(Map<String, int> key) {
  if (key.isEmpty) return 0;
  const sustenidos = 'fcgdaeb';
  const bemois = 'beadgcf';
  final valores = key.values.toSet();
  if (valores.length != 1) return null;
  final n = key.length;
  if (valores.single == 1 &&
      sustenidos.substring(0, n).split('').toSet().containsAll(key.keys)) {
    return n;
  }
  if (valores.single == -1 &&
      bemois.substring(0, n).split('').toSet().containsAll(key.keys)) {
    return -n;
  }
  return null;
}

/// `[compasso, quintas]` no início de cada mudança de armadura, só do timemap
/// e do pitchpos já carregados (é o custo do aviso do Q00).
List<(int, int?)> _armaduras(VsbDocument doc) {
  final eventos = doc.pitchPos!.events;
  var compasso = 0;
  var ativo = false;
  final porCompasso = <int, int?>{};
  for (final entrada in doc.timemap!) {
    final medida = entrada.measureOn;
    if (medida != null) {
      ativo = !_rend.hasMatch(medida);
      if (ativo) compasso++;
    }
    if (!ativo) continue;
    for (final id in entrada.on) {
      final evento = eventos[id];
      if (evento != null && !porCompasso.containsKey(compasso)) {
        porCompasso[compasso] = _quintas(evento.key);
      }
    }
  }
  final mudancas = <(int, int?)>[];
  Object? vigente = '?';
  for (final c in porCompasso.keys.toList()..sort()) {
    if (porCompasso[c] != vigente) {
      mudancas.add((c, porCompasso[c]));
      vigente = porCompasso[c];
    }
  }
  return mudancas;
}

Future<(VsbDocument, int)> _render(
  File musicxml, {
  String? transpose,
  bool seed = false,
}) async {
  final watch = Stopwatch()..start();
  final doc = await renderBytes(
    musicxml.readAsBytesSync(),
    musicxml.uri.pathSegments.last,
    options: {if (seed) 'xmlIdSeed': 1, 'transpose': ?transpose},
  );
  return (doc, watch.elapsedMilliseconds);
}

int _mediana(List<int> v) => (List.of(v)..sort())[v.length ~/ 2];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pular = Platform.environment['Q01_TRANSPOSE'] != '1'
      ? 'rode com Q01_TRANSPOSE=1 (precisa do Hymn_Grabber e da libverovio.so)'
      : (!verovioAvailable ? 'sem a libverovio.so do bridge' : null);

  for (final h in _hinos) {
    test(
      'hino ${h.numero}: transpose "${h.intervalo}" pelo caminho do app',
      () async {
        final arquivo = _musicxml(h.numero);
        // Alterna original e transposto, 5 vezes cada; o primeiro par aquece.
        final tOrig = <int>[], tTransp = <int>[];
        VsbDocument? orig, transp;
        for (var i = 0; i < 6; i++) {
          final (o, to) = await _render(arquivo, seed: true);
          final (t, tt) = await _render(
            arquivo,
            transpose: h.intervalo,
            seed: true,
          );
          orig = o;
          transp = t;
          if (i > 0) {
            tOrig.add(to);
            tTransp.add(tt);
          }
        }
        final a = orig!.midi!.notes, b = transp!.midi!.notes;
        expect(b.length, a.length);
        for (var i = 0; i < a.length; i++) {
          expect(
            b[i].id,
            a[i].id,
            reason: 'mesmo id com a mesma semente (nota $i)',
          );
          expect(b[i].pitch, a[i].pitch + h.k, reason: 'nota $i');
          expect(b[i].onMs, a[i].onMs);
          expect(b[i].offMs, a[i].offMs);
          expect(
            [b[i].staff, b[i].layer, b[i].tied],
            [a[i].staff, a[i].layer, a[i].tied],
          );
        }
        final tmO = orig.timemap!, tmT = transp.timemap!;
        expect(tmT.length, tmO.length);
        for (var i = 0; i < tmO.length; i++) {
          expect(tmT[i].tstamp, tmO[i].tstamp);
          expect(tmT[i].on, tmO[i].on);
          expect(tmT[i].off, tmO[i].off);
        }

        final antes = _armaduras(orig), depois = _armaduras(transp);
        expect(antes.first, (1, h.fifths));
        expect(depois.first, (1, 0), reason: 'armadura inicial vazia');

        // Custo da leitura das armaduras: um laço sobre timemap + pitchpos.
        final watch = Stopwatch()..start();
        for (var i = 0; i < 100; i++) {
          _armaduras(transp);
        }
        final leituraUs = watch.elapsedMicroseconds / 100;

        final repeticoes = a.where((n) => _rend.hasMatch(n.id)).length;
        // ignore: avoid_print
        print(
          'hino ${h.numero} (${h.fifths >= 0 ? '+' : ''}${h.fifths}, ${h.intervalo}): '
          '${a.length} notas ($repeticoes -rend), todas k=${h.k}; '
          'render original ${_mediana(tOrig)} ms, transposto ${_mediana(tTransp)} ms '
          '(medianas de 5; tempos ${tOrig.join('/')} vs ${tTransp.join('/')}); '
          'armaduras $antes → $depois; ler as armaduras ${leituraUs.toStringAsFixed(0)} µs',
        );
      },
      skip: pular,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  test('sem semente os ids mudam a cada render, a música não', () async {
    final arquivo = _musicxml('013');
    final (a, _) = await _render(arquivo);
    final (b, _) = await _render(arquivo);
    final na = a.midi!.notes, nb = b.midi!.notes;
    expect(nb.length, na.length);
    expect(
      [for (final n in nb) (n.pitch, n.onMs, n.offMs, n.staff, n.layer)],
      [for (final n in na) (n.pitch, n.onMs, n.offMs, n.staff, n.layer)],
    );
    // ignore: avoid_print
    print(
      'sem semente: mesmos ids nos dois renders? '
      '${[for (final n in na) n.id].toString() == [for (final n in nb) n.id].toString()}',
    );
  }, skip: pular);
}
