//! `zywny_audio` — protótipo (K01): abre a saída de áudio padrão com
//! `cpal`, carrega um `.sf2` com `rustysynth` e toca uma escala de teste ou
//! um arquivo `.mid`, medindo tamanho de buffer, latência e underruns.
//!
//! `cargo run --release --example play -- <soundfont.sf2> scale|<arquivo.mid>`

use std::fs::File;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{bail, Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{BufferSize, SampleFormat, StreamConfig, SupportedBufferSize};
use rustysynth::{MidiFile, MidiFileSequencer, SoundFont, Synthesizer, SynthesizerSettings};

/// Buffer pequeno pedido ao dispositivo.
const REQUESTED_BUFFER_FRAMES: u32 = 256;
/// Folga do buffer pré-alocado do lado do callback: bem acima de qualquer
/// tamanho de bloco realista que um backend peça.
const PREALLOC_FRAMES: usize = 8192;
/// Quantos callbacks iniciais entram na média/máximo de latência impressos.
const LATENCY_SAMPLE_COUNT: u64 = 200;
/// Escala de dó maior (C4-C5), uma oitava.
const SCALE_KEYS: [i32; 8] = [60, 62, 64, 65, 67, 69, 71, 72];
/// Cauda de silêncio depois do fim da agenda/peça, para o release da
/// última nota não ser cortado pelo fim do processo.
const TAIL: Duration = Duration::from_millis(800);

/// Um evento agendado da escala de teste: liga ou desliga [key] no quadro
/// [frame], contado desde o início da reprodução.
struct ScaleEvent {
    frame: u64,
    key: i32,
    on: bool,
}

/// Agenda da escala (nota de 450 ms + 50 ms de silêncio entre elas, a
/// `sample_rate`) e a duração total até o fim da última nota, em quadros.
fn build_scale(sample_rate: i32) -> (Vec<ScaleEvent>, u64) {
    let note = Duration::from_millis(450);
    let gap = Duration::from_millis(50);
    let note_frames = (note.as_secs_f64() * sample_rate as f64).round() as u64;
    let gap_frames = (gap.as_secs_f64() * sample_rate as f64).round() as u64;
    let mut events = Vec::with_capacity(SCALE_KEYS.len() * 2);
    let mut frame = 0u64;
    for &key in SCALE_KEYS.iter() {
        events.push(ScaleEvent {
            frame,
            key,
            on: true,
        });
        events.push(ScaleEvent {
            frame: frame + note_frames,
            key,
            on: false,
        });
        frame += note_frames + gap_frames;
    }
    (events, frame)
}

/// O que está tocando: a escala (agenda própria, manual) ou um `.mid`
/// (agenda do `MidiFileSequencer`, do rustysynth).
enum Player {
    Scale {
        synth: Synthesizer,
        events: Vec<ScaleEvent>,
        next: usize,
    },
    Midi {
        sequencer: MidiFileSequencer,
    },
}

impl Player {
    /// Renderiza um bloco, aplicando antes dele os eventos da escala cujo
    /// `frame` cai dentro do bloco. Granularidade de bloco (~5 ms a 256
    /// quadros/48 kHz): suficiente para o protótipo — a agenda por amostra
    /// exata é K02.
    fn render(&mut self, elapsed_frames: u64, left: &mut [f32], right: &mut [f32]) {
        match self {
            Player::Scale {
                synth,
                events,
                next,
            } => {
                let block_end = elapsed_frames + left.len() as u64;
                while *next < events.len() && events[*next].frame < block_end {
                    let e = &events[*next];
                    if e.on {
                        synth.note_on(0, e.key, 100);
                    } else {
                        synth.note_off(0, e.key);
                    }
                    *next += 1;
                }
                synth.render(left, right);
            }
            Player::Midi { sequencer } => sequencer.render(left, right),
        }
    }
}

/// Latência (`playback - callback`) acumulada sem lock: só os primeiros
/// [LATENCY_SAMPLE_COUNT] callbacks contam, os `Ordering::Relaxed` bastam
/// porque não há dado nenhum sincronizado por eles (só as três contagens
/// entre si).
#[derive(Default)]
struct LatencyStats {
    count: AtomicU64,
    sum_nanos: AtomicU64,
    max_nanos: AtomicU64,
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let usage = "uso: play <soundfont.sf2> scale|<arquivo.mid>";
    let sf2_path = args.next().context(usage)?;
    let mode = args.next().context(usage)?;

    let sound_font = Arc::new(
        SoundFont::new(&mut File::open(&sf2_path).with_context(|| format!("abrindo {sf2_path}"))?)
            .with_context(|| format!("lendo soundfont {sf2_path}"))?,
    );

    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .context("nenhum dispositivo de saída padrão")?;
    println!("host: {:?}", host.id());
    println!(
        "device: {}",
        device
            .id()
            .map(|id| id.to_string())
            .unwrap_or_else(|_| "?".into())
    );

    let default_config = device
        .default_output_config()
        .context("sem configuração de saída padrão")?;
    if default_config.sample_format() != SampleFormat::F32 {
        bail!(
            "formato {:?} não suportado por este protótipo (só f32) — registre e ajuste \
             se um dispositivo divergir",
            default_config.sample_format()
        );
    }
    let channels = default_config.channels() as usize;
    let sample_rate = default_config.sample_rate();

    let buffer_size = match default_config.buffer_size() {
        SupportedBufferSize::Range { min, max }
            if (*min..=*max).contains(&REQUESTED_BUFFER_FRAMES) =>
        {
            BufferSize::Fixed(REQUESTED_BUFFER_FRAMES)
        }
        _ => BufferSize::Default,
    };
    println!(
        "sample_rate: {sample_rate}  channels: {channels}  format: {:?}",
        default_config.sample_format()
    );
    println!("buffer pedido: {REQUESTED_BUFFER_FRAMES}  buffer obtido: {buffer_size:?}");

    let config = StreamConfig {
        channels: channels as u16,
        sample_rate,
        buffer_size,
    };

    let settings = SynthesizerSettings::new(sample_rate as i32);
    let synth = Synthesizer::new(&sound_font, &settings).context("criando o sintetizador")?;

    let (mut player, total_frames) = match mode.as_str() {
        "scale" => {
            let (events, total_frames) = build_scale(sample_rate as i32);
            (
                Player::Scale {
                    synth,
                    events,
                    next: 0,
                },
                total_frames,
            )
        }
        path => {
            let midi_file = Arc::new(
                MidiFile::new(&mut File::open(path).with_context(|| format!("abrindo {path}"))?)
                    .with_context(|| format!("lendo midi {path}"))?,
            );
            let total_frames = (midi_file.get_length() * sample_rate as f64).round() as u64;
            let mut sequencer = MidiFileSequencer::new(synth);
            sequencer.play(&midi_file, false);
            (Player::Midi { sequencer }, total_frames)
        }
    };

    let mut left_buf = vec![0f32; PREALLOC_FRAMES];
    let mut right_buf = vec![0f32; PREALLOC_FRAMES];
    let mut elapsed_frames = 0u64;

    let stats = Arc::new(LatencyStats::default());
    let stats_cb = Arc::clone(&stats);
    let underruns = Arc::new(AtomicU64::new(0));
    let underruns_cb = Arc::clone(&underruns);

    let stream = device.build_output_stream(
        config,
        move |data: &mut [f32], info: &cpal::OutputCallbackInfo| {
            let frames = data.len() / channels;
            debug_assert!(
                frames <= PREALLOC_FRAMES,
                "buffer do host maior que a pré-alocação"
            );
            let frames = frames.min(PREALLOC_FRAMES);
            let left = &mut left_buf[..frames];
            let right = &mut right_buf[..frames];
            player.render(elapsed_frames, left, right);
            elapsed_frames += frames as u64;

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

            if stats_cb.count.load(Ordering::Relaxed) < LATENCY_SAMPLE_COUNT {
                let ts = info.timestamp();
                let latency = ts.playback.duration_since(ts.callback);
                let nanos = latency.as_nanos() as u64;
                stats_cb.sum_nanos.fetch_add(nanos, Ordering::Relaxed);
                stats_cb.max_nanos.fetch_max(nanos, Ordering::Relaxed);
                stats_cb.count.fetch_add(1, Ordering::Relaxed);
            }
        },
        move |err| {
            if err.kind() == cpal::ErrorKind::Xrun {
                underruns_cb.fetch_add(1, Ordering::Relaxed);
            } else {
                eprintln!("erro no stream de áudio: {err}");
            }
        },
        None,
    )?;
    stream.play()?;

    let total_secs = total_frames as f64 / sample_rate as f64 + TAIL.as_secs_f64();
    std::thread::sleep(Duration::from_secs_f64(total_secs));
    drop(stream);

    let n = stats.count.load(Ordering::Relaxed).max(1);
    let avg_ms = stats.sum_nanos.load(Ordering::Relaxed) as f64 / n as f64 / 1e6;
    let max_ms = stats.max_nanos.load(Ordering::Relaxed) as f64 / 1e6;
    println!(
        "latência estimada (playback - callback), {} callbacks: média {:.2} ms, máxima {:.2} ms",
        n, avg_ms, max_ms
    );
    println!("underruns: {}", underruns.load(Ordering::Relaxed));

    Ok(())
}
