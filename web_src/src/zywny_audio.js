// Som do zywny na Web (W04): SpessaSynth num AudioWorklet, atrás de funções
// simples que o Dart chama por `dart:js_interop` (lib/audio/web_sound_engine.dart).
//
// Relógio: tudo em segundos do `AudioContext` — o mesmo do agendador de K04.
// `now()` é o que se OUVE agora (a amostra que está saindo), `earliest()` é o
// que ainda dá para agendar (a amostra que está sendo gerada); a diferença é a
// latência de saída.
//
// Agenda: o worklet aceita eventos com horário (`{time}`), mas não dá para
// cancelá-los depois de enviados. Por isso a fila fica aqui, e um evento só vai
// para o worklet [LEAD] segundos antes da hora — pausar/seek (`clear`) descarta
// quase tudo e neutraliza só o que já estava a caminho.
import { WorkletSynthesizer } from 'spessasynth_lib';

const LEAD = 0.1;
const TICK_MS = 25;
const NOTE_ON = 0x90;
const NOTE_OFF = 0x80;

let ctx = null;
let synth = null;
let analyser = null;
let timer = 0;
let pending = []; // {t, m} ainda aqui, em ordem de t
let inflight = []; // já no worklet, ainda não tocados

/** Cria o contexto de áudio e o sintetizador. Devolve a taxa de amostragem. */
export async function init() {
  if (ctx) return ctx.sampleRate;
  ctx = new AudioContext({ latencyHint: 'interactive' });
  await ctx.audioWorklet.addModule(
    new URL('./spessasynth_processor.min.js', import.meta.url).href,
  );
  synth = new WorkletSynthesizer(ctx);
  analyser = ctx.createAnalyser();
  analyser.fftSize = 2048;
  synth.connect(analyser);
  analyser.connect(ctx.destination);
  await synth.isReady;
  resume();
  return ctx.sampleRate;
}

/** Troca o soundfont (SF2/SF3/DLS). `bytes` é um Uint8Array (copiado aqui). */
export async function loadSoundFont(bytes) {
  const copy = bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  );
  // Mesmo id: um soundfont novo substitui o anterior.
  await synth.soundBankManager.addSoundBank(copy, 'main');
}

// O navegador só deixa o áudio correr depois de um gesto do usuário; chamado
// a cada play/envio, religa assim que houver um.
function resume() {
  if (ctx && ctx.state !== 'running') ctx.resume().catch(() => {});
}

export function state() {
  return ctx ? ctx.state : 'none';
}

export function latency() {
  return ctx ? ctx.outputLatency || ctx.baseLatency || 0 : 0;
}

export function baseLatency() {
  return ctx ? ctx.baseLatency || 0 : 0;
}

export function outputLatency() {
  return ctx ? ctx.outputLatency || 0 : 0;
}

/** O que se ouve agora, em segundos do contexto. */
export function now() {
  if (ctx.state === 'running') {
    const ts = ctx.getOutputTimestamp();
    if (ts.performanceTime > 0) {
      return ts.contextTime + (performance.now() - ts.performanceTime) / 1000;
    }
  }
  return Math.max(0, ctx.currentTime - latency());
}

/** O menor horário que ainda dá para agendar. */
export function earliest() {
  return ctx.currentTime;
}

const length = (status) => {
  const kind = status & 0xf0;
  return kind === 0xc0 || kind === 0xd0 ? 2 : 3;
};

/** Toca já: o monitor do teclado (M02). */
export function send(status, d1, d2) {
  resume();
  synth.sendMessage([status, d1, d2].slice(0, length(status)));
}

/**
 * Agenda em lote. `times` é um Float64Array (segundos do contexto) e `bytes`
 * um Uint8Array com 3 bytes (status, d1, d2) por evento.
 */
export function schedule(times, bytes) {
  resume();
  for (let i = 0; i < times.length; i++) {
    pending.push({
      t: times[i],
      m: [bytes[3 * i], bytes[3 * i + 1], bytes[3 * i + 2]].slice(
        0,
        length(bytes[3 * i]),
      ),
    });
  }
  // Estável: eventos do mesmo instante (um noteOff antes do noteOn da mesma
  // tecla) mantêm a ordem em que chegaram.
  pending.sort((a, b) => a.t - b.t);
  pump();
  if (pending.length && !timer) timer = setInterval(pump, TICK_MS);
}

function pump() {
  const cur = ctx.currentTime;
  const horizon = cur + LEAD;
  let n = 0;
  while (n < pending.length && pending[n].t <= horizon) {
    const e = pending[n++];
    synth.sendMessage(e.m, 0, { time: e.t });
    inflight.push(e);
  }
  if (n) pending = pending.slice(n);
  inflight = inflight.filter((e) => e.t > cur);
  if (!pending.length && timer) {
    clearInterval(timer);
    timer = 0;
  }
}

/**
 * Descarta a agenda. O que já foi para o worklet não volta: cada nota-on que
 * ainda não tocou ganha um nota-off logo em seguida, senão ficaria presa.
 */
export function clear() {
  pending = [];
  if (timer) {
    clearInterval(timer);
    timer = 0;
  }
  const cur = ctx.currentTime;
  for (const e of inflight) {
    if ((e.m[0] & 0xf0) !== NOTE_ON || e.m[2] === 0) continue;
    const t = Math.max(e.t, cur + 0.005) + 0.001;
    synth.sendMessage([NOTE_OFF | (e.m[0] & 0x0f), e.m[1], 0], 0, { time: t });
  }
  inflight = [];
}

/** Silencia tudo e limpa a agenda. */
export function allOff() {
  clear();
  synth.stopAll(true);
  for (let ch = 0; ch < 16; ch++) synth.sendMessage([0xb0 | ch, 64, 0]);
}

/** Maior amplitude (0..1) do que está saindo — só para testar sem ouvir. */
export function peak() {
  const buf = new Float32Array(analyser.fftSize);
  analyser.getFloatTimeDomainData(buf);
  let max = 0;
  for (const v of buf) max = Math.max(max, Math.abs(v));
  return max;
}

export function dispose() {
  clear();
  if (synth) synth.destroy();
  if (ctx) ctx.close().catch(() => {});
  ctx = synth = analyser = null;
}
