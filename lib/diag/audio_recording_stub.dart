import 'audio_recording_service.dart';

AudioRecordingService createAudioRecordingService() => _Unsupported();

class _Unsupported implements AudioRecordingService {
  @override
  Future<bool> start() async => false;

  @override
  Future<AudioRecordingResult?> stop() async => null;

  @override
  Future<void> dispose() async {}
}
