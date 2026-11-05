import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zywny_diag/diag_log.dart';

import 'audio_recording_service.dart';

AudioRecordingService createAudioRecordingService() => _RecordService();

/// Quantas gravações antigas ficam na pasta do app.
const int _keepRecordings = 10;

/// A pasta (dentro de Downloads) onde as gravações ficam no Android.
const String _downloadsFolder = 'Zywny';

/// AAC a 160 kbps, mono, em `.m4a`: o codificador é do sistema (Android, iOS,
/// desktop) e o arquivo fica uma fração do `.wav`.
const int _bitRate = 160000;
const String _extension = 'm4a';

const bool audioRecordingSupported = true;

String audioRecordingsFolderLabel() =>
    Platform.isAndroid ? 'Download/$_downloadsFolder' : 'pasta de dados do app';

Future<Directory> _recordingsDir() async {
  var base = Platform.isAndroid ? await getExternalStorageDirectory() : null;
  base ??= await getApplicationSupportDirectory();
  return Directory('${base.path}/gravacoes')..createSync(recursive: true);
}

/// Abre a pasta das gravações no gerenciador de arquivos. `false` se o
/// sistema não achou um aplicativo para isso.
Future<bool> openAudioRecordingsFolder() async {
  try {
    if (Platform.isAndroid) {
      // A pasta Zywny só existe depois da primeira gravação: sem ela, abre
      // Download.
      for (final doc in const ['Download%2F$_downloadsFolder', 'Download']) {
        try {
          await AndroidIntent(
            action: 'action_view',
            data:
                'content://com.android.externalstorage.documents/document/'
                'primary%3A$doc',
            type: 'vnd.android.document/directory',
            flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
          ).launch();
          return true;
        } on Object {
          // tenta a próxima
        }
      }
      return false;
    }
    final dir = await _recordingsDir();
    return await launchUrl(Uri.directory(dir.path));
  } on Object catch (e) {
    DiagLog.log('gravacao', 'não abriu a pasta: $e');
    return false;
  }
}

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
      final dir = await _recordingsDir();
      _dropOld(dir);
      final now = DateTime.now();
      final path = '${dir.path}/zywny-audio-${_stamp(now)}.$_extension';
      // Sem ganho automático, eco nem redução de ruído: o que se quer é o
      // som como chegou ao microfone.
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: _bitRate,
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
