//! Núcleo do motor de áudio (K02): estado do sintetizador, fila de comandos
//! do controle para o áudio (SPSC sem lock, `rtrb`), agenda por amostra e
//! relógio. [ZyEngine] é a metade "controle" (chamada do isolate principal
//! do Dart via `ffi.rs`, ou direto do Rust em `examples/schedule.rs`);
//! [EngineCore] é a metade "áudio" — só o callback do `cpal` a toca.
//!
//! RELÓGIO: `frames_rendered` + `cb_instant_nanos` formam um par
//! consistente, atualizado no FIM de cada callback (depois de renderizar),
//! que qualquer thread pode extrapolar a qualquer instante — só aritmética
//! sobre `std::time::Instant` monotônico, nunca `DateTime::now()`.
//! [ZyEngine::render_frame] é essa extrapolação pura; [ZyEngine::now_frame]
//! subtrai a latência de saída estimada (o que se OUVE, não o que está
//! sendo calculado).
//!
//! AGENDA: comandos chegam por uma fila SPSC (`rtrb`) do controle para o
//! áudio — o produtor é protegido por um `Mutex` (só do lado de controle;
//! o consumidor mora exclusivamente no callback de áudio, sem lock nenhum).
//! No início de cada callback, a fila é drenada para um heap de capacidade
//! fixa (cheio, descarta e conta em `dropped_events` — nunca aloca). O
//! bloco é então renderizado em sub-blocos cortados exatamente nos `frame`
//! dos eventos vencidos: raia até o evento, aplica, continua —
//! [render_block].
//!
//! CARREGAR SF2: [ZyEngine::load_sf2] derruba o `cpal::Stream` atual (se
//! houver), cria um `Synthesizer` novo e uma fila nova (a antiga e o que
//! estava nela se perdem — documentado) e sobe um stream novo.
//! `frames_rendered`/`cb_instant_nanos` são `Arc`s preservados através da
//! troca, não recriados: o relógio continua monotônico.

use std::collections::BinaryHeap;
use std::io::Cursor;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use anyhow::{bail, Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{BufferSize, SampleFormat, StreamConfig, SupportedBufferSize};
use rtrb::RingBuffer;
use rustysynth::{SoundFont, Synthesizer, SynthesizerSettings};

/// Capacidade fixa do heap de eventos agendados: cheio, descarta e conta em
/// `dropped_events` — nunca aloca no callback.
const SCHEDULE_CAPACITY: usize = 16_384;
/// Capacidade da fila SPSC controle → áudio (comandos, não só eventos
/// agendados — `zy_send`/`zy_all_notes_off`/etc. também passam por ela).
const RING_CAPACITY: usize = 4_096;
/// Folga do buffer pré-alocado do callback, em quadros.
const PREALLOC_FRAMES: usize = 8_192;
/// Buffer pequeno pedido ao dispositivo por padrão (ver K01).
pub const DEFAULT_BUFFER_FRAMES: i32 = 256;

/// Um evento MIDI cru (status, d1, d2), como a API C recebe e como o
/// `Synthesizer::process_midi_message` consome.
pub type RawMidi = [u8; 3];

#[derive(Clone, Copy)]
struct HeapEvent {
    frame: u64,
    msg: RawMidi,
}
impl PartialEq for HeapEvent {
    fn eq(&self, other: &Self) -> bool {
        self.frame == other.frame
    }
}
impl Eq for HeapEvent {}
impl PartialOrd for HeapEvent {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for HeapEvent {
    // Invertido: `BinaryHeap` é um max-heap; queremos o MENOR `frame` no
    // topo (o próximo evento a vencer).
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        other.frame.cmp(&self.frame)
    }
}

enum Command {
    Note { frame: u64, msg: RawMidi },
    ClearScheduled,
    AllNotesOff,
    SetGain(f32),
}

/// Renderiza `left`/`right` (mesmo tamanho) a partir do quadro `start_frame`
/// (o primeiro quadro do bloco), aplicando antes cada evento vencido do
/// `heap` exatamente no quadro em que ele acontece: corta o bloco ali,
/// aplica, continua. Eventos "no passado" (`frame` < `start_frame` — ex.:
/// um `zy_send`, cujo `frame` é sempre 0) aplicam no início do bloco.
///
/// A precisão real fica limitada ao bloco interno do rustysynth (64
/// quadros, o `block_size` padrão de `SynthesizerSettings`): uma nota que
/// liga no meio de um bloco de 64 já em andamento só soa a partir do
/// próximo — ver K02, critério 1.
fn render_block(
    synth: &mut Synthesizer,
    heap: &mut BinaryHeap<HeapEvent>,
    start_frame: u64,
    left: &mut [f32],
    right: &mut [f32],
) {
    let block_len = left.len();
    let end_frame = start_frame + block_len as u64;
    let mut cursor = 0usize;
    while let Some(top) = heap.peek() {
        if top.frame >= end_frame {
            break;
        }
        let offset = top.frame.saturating_sub(start_frame).min(block_len as u64) as usize;
        if offset > cursor {
            synth.render(&mut left[cursor..offset], &mut right[cursor..offset]);
            cursor = offset;
        }
        let e = heap.pop().expect("peek acabou de confirmar um elemento");
        synth.process_midi_message(0, e.msg[0] as i32, e.msg[1] as i32, e.msg[2] as i32);
    }
    if cursor < block_len {
        synth.render(&mut left[cursor..], &mut right[cursor..]);
    }
}

/// A metade "áudio": só o callback do `cpal` a toca. `dropped_events` é
/// compartilhado com [ZyEngine] (mesmo `Arc`) para `zy_stat` ler de fora.
struct EngineCore {
    synth: Synthesizer,
    heap: BinaryHeap<HeapEvent>,
    dropped_events: Arc<AtomicU64>,
}

impl EngineCore {
    fn new(synth: Synthesizer, dropped_events: Arc<AtomicU64>) -> Self {
        Self {
            synth,
            heap: BinaryHeap::with_capacity(SCHEDULE_CAPACITY),
            dropped_events,
        }
    }

    fn push_scheduled(&mut self, frame: u64, msg: RawMidi) {
        if self.heap.len() < SCHEDULE_CAPACITY {
            self.heap.push(HeapEvent { frame, msg });
        } else {
            self.dropped_events.fetch_add(1, Ordering::Relaxed);
        }
    }

    fn apply_command(&mut self, cmd: Command) {
        match cmd {
            Command::Note { frame, msg } => self.push_scheduled(frame, msg),
            Command::ClearScheduled => self.heap.clear(),
            Command::AllNotesOff => {
                self.heap.clear();
                for channel in 0..16 {
                    self.synth.process_midi_message(channel, 0xB0, 123, 0);
                    self.synth.process_midi_message(channel, 0xB0, 64, 0);
                }
            }
            Command::SetGain(gain) => self.synth.set_master_volume(gain),
        }
    }

    fn render(&mut self, start_frame: u64, left: &mut [f32], right: &mut [f32]) {
        render_block(&mut self.synth, &mut self.heap, start_frame, left, right);
    }

    #[cfg(test)]
    fn heap_len(&self) -> usize {
        self.heap.len()
    }
}

/// Extrapola, a partir de um par (quadros, instante) consistente e do
/// instante atual, quantos quadros já teriam sido produzidos — pura
/// aritmética sobre nanossegundos monotônicos.
fn extrapolate_frame(
    frames_at_anchor: u64,
    anchor_nanos: u64,
    now_nanos: u64,
    sample_rate: i32,
) -> u64 {
    let elapsed_nanos = now_nanos.saturating_sub(anchor_nanos) as u128;
    let elapsed_frames = elapsed_nanos * sample_rate as u128 / 1_000_000_000;
    frames_at_anchor + elapsed_frames as u64
}

fn nanos_to_frames(nanos: u64, sample_rate: i32) -> u64 {
    (nanos as u128 * sample_rate as u128 / 1_000_000_000) as u64
}

/// Qual estatística [ZyEngine::stat] devolve (espelha `ZY_STAT_*` do
/// header C).
#[derive(Clone, Copy)]
pub enum Stat {
    Underruns,
    DroppedEvents,
}

/// A metade "controle": chamada do isolate principal do Dart (via
/// `ffi.rs`) ou direto do Rust (`examples/schedule.rs`). [ZyEngine::new]
/// só abre o dispositivo; [ZyEngine::load_sf2] é o que de fato cria o
/// sintetizador e sobe o `cpal::Stream` — chamável de novo depois, para
/// trocar de soundfont em quente.
pub struct ZyEngine {
    device: cpal::Device,
    config: StreamConfig,
    sample_rate: i32,
    stream: Option<cpal::Stream>,
    producer: Mutex<rtrb::Producer<Command>>,
    frames_rendered: Arc<AtomicU64>,
    cb_instant_nanos: Arc<AtomicU64>,
    latency_nanos: Arc<AtomicU64>,
    dropped_events: Arc<AtomicU64>,
    underruns: Arc<AtomicU64>,
    epoch: Instant,
}

impl ZyEngine {
    /// Abre o host/dispositivo de áudio padrão. Não toca nada ainda:
    /// [ZyEngine::load_sf2] é obrigatório antes de qualquer som.
    pub fn new(preferred_buffer_frames: i32) -> Result<Self> {
        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .context("nenhum dispositivo de saída padrão")?;
        let default_config = device
            .default_output_config()
            .context("sem configuração de saída padrão")?;
        if default_config.sample_format() != SampleFormat::F32 {
            bail!(
                "formato {:?} não suportado (só f32)",
                default_config.sample_format()
            );
        }
        let channels = default_config.channels();
        let sample_rate = default_config.sample_rate();
        let preferred = preferred_buffer_frames.max(0) as u32;
        let buffer_size = match default_config.buffer_size() {
            SupportedBufferSize::Range { min, max } if (*min..=*max).contains(&preferred) => {
                BufferSize::Fixed(preferred)
            }
            _ => BufferSize::Default,
        };
        let config = StreamConfig {
            channels,
            sample_rate,
            buffer_size,
        };
        let (producer, _consumer) = RingBuffer::<Command>::new(RING_CAPACITY);
        Ok(Self {
            device,
            config,
            sample_rate: sample_rate as i32,
            stream: None,
            producer: Mutex::new(producer),
            frames_rendered: Arc::new(AtomicU64::new(0)),
            cb_instant_nanos: Arc::new(AtomicU64::new(0)),
            latency_nanos: Arc::new(AtomicU64::new(0)),
            dropped_events: Arc::new(AtomicU64::new(0)),
            underruns: Arc::new(AtomicU64::new(0)),
            epoch: Instant::now(),
        })
    }

    pub fn sample_rate(&self) -> i32 {
        self.sample_rate
    }

    /// Carrega um `.sf2` (por bytes) e (re)inicia o stream de áudio. Para o
    /// stream anterior se houver um, recria o `Synthesizer` e a fila de
    /// comandos (a agenda pendente se perde — documentado);
    /// `frames_rendered`/`cb_instant_nanos` continuam monotônicos.
    pub fn load_sf2(&mut self, bytes: &[u8]) -> Result<()> {
        let sound_font =
            Arc::new(SoundFont::new(&mut Cursor::new(bytes)).context("lendo soundfont")?);
        let settings = SynthesizerSettings::new(self.sample_rate);
        let synth = Synthesizer::new(&sound_font, &settings).context("criando o sintetizador")?;

        // Derruba o stream anterior ANTES de trocar a fila: garante que o
        // callback antigo (se ainda em voo) não lê um `Consumer` já
        // substituído por baixo dele.
        self.stream = None;

        let (producer, mut consumer) = RingBuffer::<Command>::new(RING_CAPACITY);
        let mut core = EngineCore::new(synth, Arc::clone(&self.dropped_events));

        let channels = self.config.channels as usize;
        let frames_rendered = Arc::clone(&self.frames_rendered);
        let cb_instant_nanos = Arc::clone(&self.cb_instant_nanos);
        let latency_nanos = Arc::clone(&self.latency_nanos);
        let underruns = Arc::clone(&self.underruns);
        let epoch = self.epoch;
        let mut left_buf = vec![0f32; PREALLOC_FRAMES];
        let mut right_buf = vec![0f32; PREALLOC_FRAMES];

        let stream = self.device.build_output_stream(
            self.config,
            move |data: &mut [f32], info: &cpal::OutputCallbackInfo| {
                while let Ok(cmd) = consumer.pop() {
                    core.apply_command(cmd);
                }

                let frames = (data.len() / channels).min(PREALLOC_FRAMES);
                let start_frame = frames_rendered.load(Ordering::Relaxed);
                let left = &mut left_buf[..frames];
                let right = &mut right_buf[..frames];
                core.render(start_frame, left, right);

                for (i, frame) in data.chunks_mut(channels).enumerate() {
                    let (l, r) = if i < frames {
                        (left[i], right[i])
                    } else {
                        (0.0, 0.0)
                    };
                    frame[0] = l;
                    if channels > 1 {
                        frame[1] = r;
                    }
                    for ch in frame.iter_mut().skip(2) {
                        *ch = 0.0;
                    }
                }

                let now_nanos = Instant::now().duration_since(epoch).as_nanos() as u64;
                frames_rendered.store(start_frame + frames as u64, Ordering::Relaxed);
                cb_instant_nanos.store(now_nanos, Ordering::Relaxed);

                let ts = info.timestamp();
                let latency = ts.playback.duration_since(ts.callback);
                latency_nanos.store(latency.as_nanos() as u64, Ordering::Relaxed);
            },
            move |err| {
                if err.kind() == cpal::ErrorKind::Xrun {
                    underruns.fetch_add(1, Ordering::Relaxed);
                } else {
                    eprintln!("zywny_audio: erro no stream de áudio: {err}");
                }
            },
            None,
        )?;
        stream.play()?;

        *self.producer.lock().unwrap_or_else(|e| e.into_inner()) = producer;
        self.stream = Some(stream);
        Ok(())
    }

    /// Toca `[status, d1, d2]` assim que possível (próximo bloco).
    pub fn send(&self, status: u8, d1: u8, d2: u8) {
        self.push_command(Command::Note {
            frame: 0,
            msg: [status, d1, d2],
        });
    }

    /// Agenda em lote; cada evento vale a partir do seu próprio `frame`
    /// (em quadros, no mesmo relógio de [ZyEngine::render_frame]).
    pub fn schedule(&self, events: &[(u64, RawMidi)]) {
        for &(frame, msg) in events {
            self.push_command(Command::Note { frame, msg });
        }
    }

    pub fn clear_scheduled(&self) {
        self.push_command(Command::ClearScheduled);
    }

    /// Limpa a agenda e desliga tudo (CC123 + CC64=0 nos 16 canais),
    /// aplicado no próximo callback.
    pub fn all_notes_off(&self) {
        self.push_command(Command::AllNotesOff);
    }

    pub fn set_gain(&self, gain: f32) {
        self.push_command(Command::SetGain(gain));
    }

    fn push_command(&self, cmd: Command) {
        let mut producer = self.producer.lock().unwrap_or_else(|e| e.into_inner());
        if producer.push(cmd).is_err() {
            self.dropped_events.fetch_add(1, Ordering::Relaxed);
        }
    }

    /// Estimativa de latência de saída, em quadros (do último callback).
    pub fn output_latency_frames(&self) -> i32 {
        nanos_to_frames(self.latency_nanos.load(Ordering::Relaxed), self.sample_rate) as i32
    }

    /// O quadro que está sendo calculado agora — o mínimo agendável.
    pub fn render_frame(&self) -> u64 {
        let frames_at_anchor = self.frames_rendered.load(Ordering::Relaxed);
        let anchor_nanos = self.cb_instant_nanos.load(Ordering::Relaxed);
        let now_nanos = Instant::now().duration_since(self.epoch).as_nanos() as u64;
        extrapolate_frame(frames_at_anchor, anchor_nanos, now_nanos, self.sample_rate)
    }

    /// O quadro que está saindo no alto-falante agora ([Self::render_frame]
    /// menos a latência de saída estimada).
    pub fn now_frame(&self) -> u64 {
        let latency_frames =
            nanos_to_frames(self.latency_nanos.load(Ordering::Relaxed), self.sample_rate);
        self.render_frame().saturating_sub(latency_frames)
    }

    pub fn stat(&self, which: Stat) -> u64 {
        match which {
            Stat::Underruns => self.underruns.load(Ordering::Relaxed),
            Stat::DroppedEvents => self.dropped_events.load(Ordering::Relaxed),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::path::{Path, PathBuf};

    const SAMPLE_RATE: i32 = 48_000;
    const BLOCK: usize = 256;

    /// `ZYWNY_TEST_SF2`, senão um GM livre já instalado no sistema (K01:
    /// `timgm6mb-soundfont`). `None`: os testes abaixo pulam (nenhum `.sf2`
    /// é versionado, D-SF continua aberta).
    fn find_test_soundfont() -> Option<PathBuf> {
        if let Ok(p) = std::env::var("ZYWNY_TEST_SF2") {
            if Path::new(&p).exists() {
                return Some(PathBuf::from(p));
            }
        }
        for c in [
            "/usr/share/sounds/sf2/TimGM6mb.sf2",
            "/usr/share/sounds/sf2/default-GM.sf2",
        ] {
            if Path::new(c).exists() {
                return Some(PathBuf::from(c));
            }
        }
        None
    }

    fn test_synth() -> Option<Synthesizer> {
        let path = find_test_soundfont()?;
        let sf = Arc::new(SoundFont::new(&mut File::open(path).unwrap()).unwrap());
        let settings = SynthesizerSettings::new(SAMPLE_RATE);
        Some(Synthesizer::new(&sf, &settings).unwrap())
    }

    fn rms(buf: &[f32]) -> f32 {
        if buf.is_empty() {
            return 0.0;
        }
        (buf.iter().map(|s| s * s).sum::<f32>() / buf.len() as f32).sqrt()
    }

    #[test]
    fn note_on_agendado_soa_no_quadro_certo() {
        let Some(synth) = test_synth() else {
            eprintln!(
                "SKIP: nenhum .sf2 de teste (defina ZYWNY_TEST_SF2 ou instale timgm6mb-soundfont)"
            );
            return;
        };
        let mut core = EngineCore::new(synth, Arc::new(AtomicU64::new(0)));
        const F: u64 = 1000;
        core.apply_command(Command::Note {
            frame: F,
            msg: [0x90, 60, 100],
        });

        let mut left = vec![0f32; BLOCK];
        let mut right = vec![0f32; BLOCK];
        let mut first_nonzero = None;
        let mut start = 0u64;
        while first_nonzero.is_none() && start < F + 4096 {
            core.render(start, &mut left, &mut right);
            for (i, (&l, &r)) in left.iter().zip(right.iter()).enumerate() {
                if l != 0.0 || r != 0.0 {
                    first_nonzero = Some(start + i as u64);
                    break;
                }
            }
            start += BLOCK as u64;
        }
        let first_nonzero = first_nonzero.expect("a nota deveria soar");
        assert!(
            first_nonzero >= F,
            "soou antes do agendado: {first_nonzero} < {F}"
        );
        assert!(
            first_nonzero - F <= 64,
            "atraso além de 1 bloco interno do rustysynth (64 quadros): {}",
            first_nonzero - F
        );
    }

    #[test]
    fn all_notes_off_silencia_ate_o_release() {
        let Some(synth) = test_synth() else {
            eprintln!("SKIP: nenhum .sf2 de teste");
            return;
        };
        let mut core = EngineCore::new(synth, Arc::new(AtomicU64::new(0)));
        core.apply_command(Command::Note {
            frame: 0,
            msg: [0x90, 60, 100],
        });

        let mut left = vec![0f32; BLOCK];
        let mut right = vec![0f32; BLOCK];
        core.render(0, &mut left, &mut right);
        assert!(
            rms(&left) > 1e-4,
            "a nota deveria estar soando antes do corte"
        );

        core.apply_command(Command::AllNotesOff);

        // O release do preset pode levar um tempo; dou até 3 s musicais.
        let release_frames = 3 * SAMPLE_RATE as u64;
        let mut start = BLOCK as u64;
        let mut silent_at = None;
        while start < release_frames {
            core.render(start, &mut left, &mut right);
            if rms(&left) < 1e-4 && rms(&right) < 1e-4 {
                silent_at = Some(start);
                break;
            }
            start += BLOCK as u64;
        }
        assert!(
            silent_at.is_some(),
            "não silenciou em até {release_frames} quadros depois do all_notes_off"
        );
    }

    #[test]
    fn heap_cheio_descarta_sem_panico() {
        let Some(synth) = test_synth() else {
            eprintln!("SKIP: nenhum .sf2 de teste");
            return;
        };
        let dropped = Arc::new(AtomicU64::new(0));
        let mut core = EngineCore::new(synth, Arc::clone(&dropped));
        for i in 0..(SCHEDULE_CAPACITY + 10) {
            core.apply_command(Command::Note {
                frame: 10_000_000 + i as u64,
                msg: [0x90, 60, 100],
            });
        }
        assert_eq!(core.heap_len(), SCHEDULE_CAPACITY);
        assert_eq!(dropped.load(Ordering::Relaxed), 10);
    }
}
