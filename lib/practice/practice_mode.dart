// R03 — o modo do treino num arquivo-folha, para `AppSettings` e a trilha
// não dependerem do controller (que puxa áudio e MIDI).

/// Margem padrão do tempo real (ver `PracticeController.rhythmToleranceMs`).
const double kDefaultRhythmToleranceMs = 75;

/// Como o treino conduz o tempo (T03).
enum PracticeMode {
  /// Modo espera (T02): o tempo para até o aluno tocar o passo.
  wait,

  /// Tempo real (T03): a música anda e cada nota recebe veredito na hora.
  realtime,
}
