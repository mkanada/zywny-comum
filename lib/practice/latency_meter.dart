// Medidor de latência do som do teclado: o app manda uma nota MIDI e escuta,
// pelo microfone, quando o som sai. Aqui fica a parte sem plataforma: o
// envelope do sinal do microfone (`MicTimeline`), a detecção da batida e a
// conta da latência (`LatencyStats`). Quem lê o microfone e manda as notas é
// `LatencyMeterRunner`.
//
// O relógio do microfone: o plugin entrega o áudio em pedaços, e o pedaço
// chega depois de captado (atraso do hardware + do canal da plataforma, com
// jitter). O instante da amostra `n` é `origem + n / taxa`, e a origem é o
// MENOR `chegada − amostras / taxa` visto: o jitter só atrasa, nunca
// adianta, então o pedaço mais rápido é o mais fiel. Sobra o atraso fixo do
// próprio microfone, que o `LatencyMeterRunner` tira com o alto-falante do
// celular como referência.
import 'dart:math' as math;
import 'dart:typed_data';

/// Largura de um bloco do envelope: 1 ms.
const double kMeterBlockSeconds = 0.001;

/// Piso absoluto da batida (RMS, 0..1): −50 dBFS. Abaixo disso é silêncio.
const double kMeterMinThreshold = 0.003;

/// A batida tem de passar disto vezes o ruído de fundo.
const double kMeterThresholdRatio = 5;

/// O ruído de fundo é medido nos [kMeterFloorSeconds] antes do envio.
const double kMeterFloorSeconds = 0.25;

/// Quanto tempo depois do envio ainda se espera a batida.
const double kMeterMaxWaitSeconds = 0.6;

/// Os blocos seguintes à batida (8 ms) têm de continuar acima do limiar:
/// estalo de um bloco só não é nota (ver `_sustained`).
const int _kSustainBlocks = 8;

/// Por que um envio não achou batida.
enum MeterMiss {
  /// Nada passou do limiar no tempo de espera.
  silent,

  /// Já havia som na hora do envio (cauda da nota anterior, ruído).
  busy,
}

/// A batida achada, ou o motivo de não ter achado.
class MeterOnset {
  const MeterOnset.at(this.seconds) : miss = null;
  const MeterOnset.missed(this.miss) : seconds = null;

  /// Instante da batida, no relógio dos carimbos de chegada.
  final double? seconds;
  final MeterMiss? miss;
}

/// O sinal do microfone em envelope (RMS a cada [kMeterBlockSeconds]) e o
/// relógio que o amarra ao do app.
class MicTimeline {
  MicTimeline({required this.sampleRate})
    : _blockSamples = math.max(1, (sampleRate * kMeterBlockSeconds).round());

  final int sampleRate;
  final int _blockSamples;

  final List<double> _envelope = [];
  double _sumSquares = 0;
  int _inBlock = 0;
  int _samples = 0;
  double _origin = double.infinity;

  /// Blocos já fechados.
  int get blocks => _envelope.length;

  /// Segundos de áudio recebidos.
  double get seconds => _samples / sampleRate;

  /// Pico do envelope nos últimos [recent] blocos (0..1), para o indicador de
  /// volume da tela.
  double level({int recent = 50}) {
    var peak = 0.0;
    for (
      var i = math.max(0, _envelope.length - recent);
      i < _envelope.length;
      i++
    ) {
      peak = math.max(peak, _envelope[i]);
    }
    return peak;
  }

  /// Soma um pedaço de PCM 16 bits mono que chegou em [arrivalSeconds] (o
  /// relógio do app, lido ao receber).
  void add(Int16List pcm, double arrivalSeconds) {
    for (final s in pcm) {
      final v = s / 32768;
      _sumSquares += v * v;
      if (++_inBlock == _blockSamples) {
        _envelope.add(math.sqrt(_sumSquares / _blockSamples));
        _sumSquares = 0;
        _inBlock = 0;
      }
    }
    _samples += pcm.length;
    _origin = math.min(_origin, arrivalSeconds - _samples / sampleRate);
  }

  double _timeOf(int block) => _origin + block * _blockSamples / sampleRate;

  int _blockAt(double seconds) =>
      ((seconds - _origin) * sampleRate / _blockSamples).floor();

  /// Pelo menos 5 dos 8 blocos a partir de [block] seguem acima de metade do
  /// limiar: a nota fica, o estalo não.
  bool _sustained(int block, double threshold) {
    var above = 0;
    for (var i = block; i < block + _kSustainBlocks; i++) {
      if (_envelope[i] >= threshold * 0.5) above++;
    }
    return above >= 5;
  }

  /// A primeira batida depois de [sentSeconds] (até [kMeterMaxWaitSeconds]).
  MeterOnset onsetAfter(double sentSeconds) {
    final from = _blockAt(sentSeconds);
    final floorFrom = math.max(
      0,
      from - (kMeterFloorSeconds / kMeterBlockSeconds).round(),
    );
    if (from < 0 || from >= _envelope.length) {
      return const MeterOnset.missed(MeterMiss.silent);
    }
    final threshold = math.max(
      kMeterMinThreshold,
      _quantile(
            _envelope.sublist(floorFrom, math.max(floorFrom + 1, from)),
            0.25,
          ) *
          kMeterThresholdRatio,
    );
    // Som já alto no instante do envio: a nota anterior ainda soa.
    final before = _envelope.sublist(math.max(0, from - 10), from);
    if (before.isNotEmpty && _mean(before) >= threshold) {
      return const MeterOnset.missed(MeterMiss.busy);
    }
    final last = math.min(
      _envelope.length - _kSustainBlocks,
      from + (kMeterMaxWaitSeconds / kMeterBlockSeconds).round(),
    );
    for (var b = from; b <= last; b++) {
      if (_envelope[b] < threshold) continue;
      if (!_sustained(b, threshold)) continue;
      // O pé da subida: volta enquanto o sinal ainda está bem acima do ruído.
      var start = b;
      final foot = threshold / kMeterThresholdRatio * 2.5;
      while (start > from && b - start < 6 && _envelope[start - 1] >= foot) {
        start--;
      }
      return MeterOnset.at(_timeOf(start));
    }
    return const MeterOnset.missed(MeterMiss.silent);
  }
}

double _mean(List<double> values) =>
    values.fold(0.0, (a, b) => a + b) / values.length;

/// O quantil [q] (0..1) de [values].
double _quantile(List<double> values, double q) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * q).round()];
}

/// Uma série de medidas (ms) já limpa: a mediana, o quanto oscila e quantas
/// valeram.
class LatencyStats {
  const LatencyStats({
    required this.medianMs,
    required this.minMs,
    required this.maxMs,
    required this.stdMs,
    required this.used,
    required this.total,
  });

  final double medianMs;
  final double minMs;
  final double maxMs;

  /// Desvio-padrão das medidas que valeram.
  final double stdMs;
  final int used;

  /// Quantos envios houve.
  final int total;

  /// Mediana das [samples], sem as que ficam a mais de [outlierMs] dela
  /// (batida falsa do ruído, nota que demorou). `null` sem nenhuma medida.
  static LatencyStats? of(
    List<double> samples, {
    required int total,
    double outlierMs = 30,
  }) {
    if (samples.isEmpty) return null;
    final first = _median(samples);
    final kept = [
      for (final s in samples)
        if ((s - first).abs() <= outlierMs) s,
    ]..sort();
    final median = _median(kept);
    final mean = _mean(kept);
    final variance =
        kept.fold(0.0, (a, b) => a + (b - mean) * (b - mean)) / kept.length;
    return LatencyStats(
      medianMs: median,
      minMs: kept.first,
      maxMs: kept.last,
      stdMs: math.sqrt(variance),
      used: kept.length,
      total: total,
    );
  }
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Como a latência [ms] soa para quem toca, em português.
String latencyVerdict(double ms) {
  if (ms < 15) return 'Excelente: não dá para sentir.';
  if (ms < 30) return 'Boa: dá para tocar junto sem sentir o atraso.';
  if (ms < 60) {
    return 'Dá para perceber e pode atrapalhar o ritmo: o som sai depois '
        'da hora.';
  }
  return 'Alta: o som sai bem depois da hora. Fio ruim, Bluetooth ou '
      'um teclado com modo de baixa latência desligado?';
}
