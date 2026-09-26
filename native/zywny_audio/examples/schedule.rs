//! `zywny_audio` — K02: agenda uma escala de dó maior a 120 bpm usando
//! `ZyEngine::render_frame() + margem` e toca, provando a agenda por
//! amostra de ponta a ponta (o teste automatizado de K02 não abre
//! dispositivo — ver `src/engine.rs`).
//!
//! `cargo run --release --example schedule -- <soundfont.sf2>`

use std::fs;
use std::time::Duration;

use anyhow::{Context, Result};
use zywny_audio::{RawMidi, Stat, ZyEngine, DEFAULT_BUFFER_FRAMES};

const SCALE_KEYS: [u8; 8] = [60, 62, 64, 65, 67, 69, 71, 72];
/// 120 bpm, semínima = 500 ms.
const BEAT: Duration = Duration::from_millis(500);
/// Folga acima do mínimo agendável (`render_frame`), para o primeiro
/// evento não perder a corrida com o próprio agendamento.
const MARGIN: Duration = Duration::from_millis(200);

fn main() -> Result<()> {
    let sf2_path = std::env::args()
        .nth(1)
        .context("uso: schedule <soundfont.sf2>")?;
    let bytes = fs::read(&sf2_path).with_context(|| format!("lendo {sf2_path}"))?;

    let mut engine =
        ZyEngine::new(DEFAULT_BUFFER_FRAMES).context("abrindo o dispositivo de áudio")?;
    engine.load_sf2(&bytes).context("carregando o soundfont")?;
    println!(
        "sample_rate: {}  latência estimada: {} quadros",
        engine.sample_rate(),
        engine.output_latency_frames()
    );

    let sample_rate = engine.sample_rate() as f64;
    let beat_frames = (BEAT.as_secs_f64() * sample_rate).round() as u64;
    let margin_frames = (MARGIN.as_secs_f64() * sample_rate).round() as u64;
    let start = engine.render_frame() + margin_frames;

    let mut events: Vec<(u64, RawMidi)> = Vec::with_capacity(SCALE_KEYS.len() * 2);
    for (i, &key) in SCALE_KEYS.iter().enumerate() {
        let on = start + i as u64 * beat_frames;
        let off = on + beat_frames - beat_frames / 10; // um traço de silêncio antes da próxima nota
        events.push((on, [0x90, key, 100]));
        events.push((off, [0x80, key, 0]));
    }
    engine.schedule(&events);

    let total_secs = SCALE_KEYS.len() as f64 * BEAT.as_secs_f64() + MARGIN.as_secs_f64() + 1.0;
    std::thread::sleep(Duration::from_secs_f64(total_secs));

    println!(
        "underruns: {}  dropped_events: {}",
        engine.stat(Stat::Underruns),
        engine.stat(Stat::DroppedEvents)
    );
    Ok(())
}
