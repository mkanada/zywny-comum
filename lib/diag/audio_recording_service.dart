import 'audio_recording_stub.dart'
    if (dart.library.io) 'audio_recording_native.dart'
    as impl;

/// O que a gravação de áudio devolve ao parar.
class AudioRecordingResult {
  const AudioRecordingResult({this.savedAt});

  /// Onde o `.wav` ficou, para o aluno achar (`null` se não gravou nada).
  final String? savedAt;
}

/// Grava o microfone em um `.wav`. Injetável: os testes trocam por um falso.
abstract class AudioRecordingService {
  /// Pede a permissão e começa a gravar. `false` se não foi possível
  /// (permissão negada, sem microfone, ou plataforma sem suporte).
  Future<bool> start();

  /// Para e guarda o arquivo. `null` se não estava gravando ou falhou.
  Future<AudioRecordingResult?> stop();

  Future<void> dispose();
}

/// O serviço da plataforma (Android, iOS, desktop). Na Web não grava.
AudioRecordingService createAudioRecordingService() =>
    impl.createAudioRecordingService();
