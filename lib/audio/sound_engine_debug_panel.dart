// O painel de debug fala com o `NativeSoundEngine` (dart:ffi, K02): fora da
// Web ele é o de verdade; na Web (W04 traz o motor de lá) fica um stub vazio.
export 'sound_engine_debug_panel_stub.dart'
    if (dart.library.io) 'sound_engine_debug_panel_native.dart';
