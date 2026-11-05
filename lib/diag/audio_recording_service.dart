import 'audio_recording_stub.dart'
    if (dart.library.io) 'audio_recording_native.dart'
    as impl;

/// O que a gravação de áudio devolve ao parar.
class AudioRecordingResult {
  const AudioRecordingResult({this.savedAt});

  /// Onde o `.m4a` ficou, para o aluno achar (`null` se não gravou nada).
  final String? savedAt;
}

/// Grava o microfone em um `.m4a` (AAC, 160 kbps). Injetável: os testes trocam por um falso.
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

/// Este aparelho grava o microfone? (Não na Web.)
bool get audioRecordingSupported => impl.audioRecordingSupported;

/// Onde as gravações ficam, em texto para o aluno (`Download/Zywny`).
String audioRecordingsFolderLabel() => impl.audioRecordingsFolderLabel();

/// Abre a pasta das gravações no gerenciador de arquivos. `false` se não deu.
Future<bool> openAudioRecordingsFolder() => impl.openAudioRecordingsFolder();
