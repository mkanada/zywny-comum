import 'dart:io';

import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:zywny_diag/diag_log.dart';

import 'audio_recording_service.dart';

AudioRecordingService createAudioRecordingService() => _RecordService();

/// Quantas gravações antigas ficam na pasta do app.
const int _keepRecordings = 10;

/// A pasta (dentro de Downloads) onde as gravações ficam no Android.
const String _downloadsFolder = 'Zywny';

class _RecordService implements AudioRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  @override
  Future<bool> start() async {
    try {
      if (!await _recorder.hasPermission()) {
        DiagLog.log('gravacao', 'permissão do microfone negada');
        return false;
      }
      var base = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : null;
      base ??= await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/gravacoes')
        ..createSync(recursive: true);
      _dropOld(dir);
      final now = DateTime.now();
      final path = '${dir.path}/zywny-audio-${_stamp(now)}.wav';
      // Sem ganho automático, eco nem redução de ruído: o que se quer é o
      // som como chegou ao microfone.
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: path,
      );
      _path = path;
      DiagLog.log('gravacao', 'começou: $path');
      return true;
    } on Object catch (e) {
      DiagLog.log('gravacao', 'não abriu o microfone: $e');
      return false;
    }
  }

  @override
  Future<AudioRecordingResult?> stop() async {
    final path = _path;
    _path = null;
    if (path == null) return null;
    try {
      await _recorder.stop();
    } on Object catch (e) {
      DiagLog.log('gravacao', 'erro ao parar: $e');
      return null;
    }
    final file = File(path);
    if (!file.existsSync()) return null;
    DiagLog.log('gravacao', 'terminou: $path (${file.lengthSync()} bytes)');
    return AudioRecordingResult(savedAt: await _toDownloads(file) ?? path);
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

/// Copia para `Download/Zywny` (MediaStore), que o aluno acha sem cabo.
/// `null` se não for Android ou se falhar: a cópia da pasta do app vale.
Future<String?> _toDownloads(File file) async {
  if (!Platform.isAndroid) return null;
  try {
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = _downloadsFolder;
    final info = await MediaStore().saveFile(
      tempFilePath: file.path,
      dirType: DirType.download,
      dirName: DirName.download,
    );
    if (info == null) return null;
    return 'Download/$_downloadsFolder/${info.name}';
  } on Object {
    return null;
  }
}

void _dropOld(Directory dir) {
  try {
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files.take(files.length - _keepRecordings + 1)) {
      f.deleteSync();
    }
  } on Object {
    // Limpeza é só conforto.
  }
}
