import 'dart:typed_data';

/// Um evento MIDI cru (`status`, `d1`, `d2`) agendado para tocar em [at] —
/// segundos do relógio de [SoundEngine.nowSeconds]/`earliestScheduleSeconds`.
class ScheduledMidi {
  const ScheduledMidi(this.at, this.status, this.d1, this.d2);

  final double at;
  final int status;
  final int d1;
  final int d2;
}

/// Interface única para "algo que faz som a partir de MIDI" (K03). Todas as
/// saídas do projeto implementam esta interface: o motor nativo
/// (`NativeSoundEngine`, sobre `zywny_audio`/K02) aqui, um teclado externo
/// (M03) e a Web (W04) depois.
///
/// Segundos (`double`) na interface, não quadros: quadros só existem dentro
/// de uma implementação nativa (`frame = (at * sampleRate).round()`) — a Web
/// usa `AudioContext.currentTime`, já em segundos, sem conversão nenhuma.
abstract class SoundEngine {
  /// Relógio do dispositivo, em segundos desde um zero arbitrário e
  /// monotônico. É o que se OUVE agora (já descontada a latência de saída).
  double get nowSeconds;

  /// Menor instante que ainda dá para agendar com precisão.
  double get earliestScheduleSeconds;

  double get outputLatencySeconds;

  /// Abre o dispositivo de áudio. Chame uma vez só; o motor sobrevive a
  /// novos `.vsb`, só [dispose] no fim de vez.
  Future<void> start();

  Future<void> loadSoundFont(Uint8List bytes);

  /// Toca `midi` (3 bytes: status, d1, d2) assim que possível — o monitor
  /// (M02), por exemplo.
  void send(List<int> midi);

  /// Agenda em lote; cada [ScheduledMidi.at] vale por si.
  void schedule(List<ScheduledMidi> events);

  void clearScheduled();

  /// Desliga tudo que estiver soando e limpa a agenda.
  void allNotesOff();

  Future<void> dispose();
}
