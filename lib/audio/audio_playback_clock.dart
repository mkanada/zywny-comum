// K04: adapta [ScoreAudioScheduler] a `PlaybackClock` (C01) — o
// `ScorePlayer` passa a ler `positionMs` do relógio do áudio a cada tick em
// vez de somar `delta * speed`. Como `SoundEngine.nowSeconds` já desconta a
// latência de saída, o destaque acende quando o som *sai*, não quando é
// calculado.

import 'package:score_bridge/score_bridge.dart';

import 'score_audio_scheduler.dart';

class AudioPlaybackClock implements PlaybackClock {
  const AudioPlaybackClock(this.scheduler);

  final ScoreAudioScheduler scheduler;

  @override
  double get positionMs => scheduler.positionMs;

  @override
  bool get isRunning => scheduler.isRunning;
}
