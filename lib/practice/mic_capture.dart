// O microfone do medidor de latência: PCM 16 bits mono, sem tratamento
// nenhum (ganho automático, cancelamento de eco e redução de ruído achatam a
// batida da nota e atrasam o sinal).
import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'package:zywny_diag/diag_log.dart';

/// Por que o microfone não abriu.
enum MicFailure { denied, unavailable }

/// Quem entrega o áudio do microfone ao medidor — injetável nos testes.
abstract class MicCapture {
  /// Taxa de amostragem do que [start] entrega (Hz).
  int get sampleRate;

  /// Pede a permissão e abre o microfone. `null` se abriu; senão o motivo.
  Future<MicFailure?> start();

  /// PCM 16 bits mono, em pedaços, enquanto aberto.
  Stream<Int16List> get chunks;

  Future<void> stop();
}

/// [MicCapture] sobre o plugin `record`.
class RecordMicCapture implements MicCapture {
  RecordMicCapture({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  static const int _rate = 44100;

  final AudioRecorder _recorder;
  final StreamController<Int16List> _chunks = StreamController.broadcast(
    sync: true,
  );
  StreamSubscription<Uint8List>? _sub;

  @override
  int get sampleRate => _rate;

  @override
  Stream<Int16List> get chunks => _chunks.stream;

  @override
  Future<MicFailure?> start() async {
    try {
      if (!await _recorder.hasPermission()) return MicFailure.denied;
      Stream<Uint8List>? stream;
      // A fonte "sem processamento" é a de menor atraso, mas nem todo
      // aparelho a tem: cai na comum.
      for (final source in [
        AndroidAudioSource.unprocessed,
        AndroidAudioSource.defaultSource,
      ]) {
        try {
          stream = await _recorder.startStream(_config(source));
          break;
        } on Object catch (e) {
          DiagLog.log('medidor', 'microfone ($source) falhou: $e');
        }
      }
      if (stream == null) return MicFailure.unavailable;
      _sub = stream.listen(
        _onBytes,
        onError: (Object e) {
          DiagLog.log('medidor', 'erro do microfone: $e');
        },
      );
      return null;
    } on Object catch (e) {
      DiagLog.log('medidor', 'microfone indisponível: $e');
      return MicFailure.unavailable;
    }
  }

  RecordConfig _config(AndroidAudioSource source) => RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: _rate,
    numChannels: 1,
    autoGain: false,
    echoCancel: false,
    noiseSuppress: false,
    androidConfig: AndroidRecordConfig(audioSource: source),
  );

  void _onBytes(Uint8List bytes) {
    if (_chunks.isClosed || bytes.length < 2) return;
    // Cópia: o plugin pode reaproveitar o buffer e o offset pode ser ímpar.
    final copy = Uint8List.fromList(bytes);
    _chunks.add(copy.buffer.asInt16List(0, copy.length ~/ 2));
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } on Object catch (e) {
      DiagLog.log('medidor', 'erro ao fechar o microfone: $e');
    }
    await _recorder.dispose();
    await _chunks.close();
  }
}
