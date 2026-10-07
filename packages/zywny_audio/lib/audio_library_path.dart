import 'dart:io';

/// Locates the native `libzywny_audio.so` (K02/K03).
///
/// Search order: explicit env override, the installed Linux bundle layout,
/// then the project source tree (covers `flutter run` from the project
/// root, or the tests from `packages/zywny_audio`). Mirrors
/// `findVerovioLibrary` in `lib/render/verovio_paths.dart`;
/// unlike Verovio, this crate lives inside this repo (`native/zywny_audio/`),
/// not an external one.
String findAudioLibrary() {
  // Android: packaged from jniLibs/<abi>/, found by bare name (K05).
  if (Platform.isAndroid) return 'libzywny_audio.so';

  final env = Platform.environment['ZYWNY_AUDIO_LIBRARY_PATH'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;

  if (!Platform.isLinux) {
    throw StateError(
      'libzywny_audio not available on ${Platform.operatingSystem} yet '
      '(only Linux and Android are supported so far).',
    );
  }

  final candidates = <String>[
    // Installed bundle: <bundle>/zywny -> <bundle>/lib/libzywny_audio.so
    // (linux/CMakeLists.txt installs it there; RPATH is $ORIGIN/lib).
    '${File(Platform.resolvedExecutable).parent.path}/lib/libzywny_audio.so',
    // Dev fallback: built in this repo via tool/build_audio_linux.sh, from
    // the project root (how `flutter run`/`just run` are normally invoked).
    'native/zywny_audio/target/release/libzywny_audio.so',
    // O mesmo, visto de packages/zywny_audio (onde os testes deste pacote
    // rodam — R15).
    '../../native/zywny_audio/target/release/libzywny_audio.so',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  throw StateError(
    'libzywny_audio.so not found. Tried:\n'
    '${candidates.join('\n')}\n'
    'Build it with tool/build_audio_linux.sh or set ZYWNY_AUDIO_LIBRARY_PATH.',
  );
}
