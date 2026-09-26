/* zywny_audio — API C do motor de áudio (K02).
 *
 * Handwritten (não gerado por cbindgen); mantenha em sincronia com
 * `src/ffi.rs`. `ZyEngine` é opaco: só o Rust sabe o que tem dentro.
 *
 * Threads: as chamadas vêm do isolate principal do Dart (um thread por vez,
 * não necessariamente sempre o mesmo do SO); o callback de áudio roda no
 * thread do cpal. Um `ZyEngine*` não é enviável para nem tocável por mais
 * de uma thread de controle ao mesmo tempo — sincronize do lado do Dart se
 * precisar.
 */
#ifndef ZYWNY_AUDIO_H
#define ZYWNY_AUDIO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaco: o motor (dispositivo de áudio + sintetizador + agenda). */
typedef struct ZyEngine ZyEngine;

/* Um evento MIDI cru agendado num quadro exato (ver zy_schedule). */
typedef struct {
  uint64_t frame;
  uint8_t status;
  uint8_t d1;
  uint8_t d2;
  uint8_t _pad;
} ZyEvent;

/* `which` de zy_stat. */
#define ZY_STAT_UNDERRUNS 0
#define ZY_STAT_DROPPED_EVENTS 1

/* Abre o host/dispositivo de áudio padrão e pede `preferred_buffer_frames`
 * de buffer (o dispositivo pode não conceder; ver zy_output_latency_frames
 * para saber a latência real). NÃO toca nada ainda: zy_engine_load_sf2 é
 * obrigatório antes de qualquer som. NULL em erro — ver zy_last_error(). */
ZyEngine *zy_engine_new(int32_t preferred_buffer_frames);

/* Carrega um `.sf2` (bytes crus, ex.: um asset lido pelo Dart) e
 * (re)inicia o stream de áudio: para o stream anterior se houver um, cria
 * um Synthesizer novo, sobe um stream novo. Qualquer coisa agendada antes
 * desta chamada é perdida. `frames_rendered`/o relógio de
 * zy_now_frame/zy_render_frame continuam monotônicos através da troca.
 * 0 em sucesso, -1 em erro (ver zy_last_error()). */
int32_t zy_engine_load_sf2(ZyEngine *engine, const uint8_t *bytes, size_t len);

/* Libera o motor (para o stream, se houver um). `engine` pode ser NULL. */
void zy_engine_free(ZyEngine *engine);

/* Sample rate do dispositivo, em Hz. */
int32_t zy_sample_rate(const ZyEngine *engine);

/* Latência de saída estimada (do último callback de áudio), em quadros. */
int32_t zy_output_latency_frames(const ZyEngine *engine);

/* O quadro que está saindo no alto-falante AGORA (já descontada a
 * latência de saída) — é o que se OUVE. */
uint64_t zy_now_frame(const ZyEngine *engine);

/* O quadro que está sendo calculado agora (sem descontar a latência) — o
 * mínimo agendável com precisão; use isto + uma margem para calcular o
 * `frame` de zy_schedule. */
uint64_t zy_render_frame(const ZyEngine *engine);

/* Toca [status, d1, d2] assim que possível (o próximo bloco de áudio). */
void zy_send(const ZyEngine *engine, uint8_t status, uint8_t d1, uint8_t d2);

/* Agenda `n` eventos em lote; cada `ZyEvent.frame` vale por si (no mesmo
 * relógio de zy_render_frame). Eventos além da capacidade da fila/agenda
 * interna são descartados e contados em ZY_STAT_DROPPED_EVENTS — nunca
 * travam nem alocam no thread de áudio. */
void zy_schedule(const ZyEngine *engine, const ZyEvent *events, size_t n);

/* Apaga toda a agenda pendente (não mexe no que já está soando). */
void zy_clear_scheduled(const ZyEngine *engine);

/* Limpa a agenda e desliga tudo (CC123 + CC64=0 nos 16 canais), aplicado
 * no próximo bloco de áudio. */
void zy_all_notes_off(const ZyEngine *engine);

/* Volume mestre (linear; 1.0 = o padrão do rustysynth). */
void zy_set_gain(const ZyEngine *engine, float gain);

/* Uma estatística cumulativa (ZY_STAT_*); outro `which` devolve 0. */
uint64_t zy_stat(const ZyEngine *engine, int32_t which);

/* Mensagem do último erro nesta thread (válida até a próxima chamada
 * desta família que falhe nesta mesma thread). NULL se não houve erro
 * ainda nesta thread. */
const char *zy_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* ZYWNY_AUDIO_H */
