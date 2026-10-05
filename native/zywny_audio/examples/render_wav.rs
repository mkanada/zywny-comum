//! I10 — render offline de áudios curtos do curso inicial com o soundfont
//! do app (D-SF), sem placa de som.
//!
//! Reaproveita o `render` do `examples/play.rs`: abre o `.sf2` com
//! `rustysynth`, agenda notas e escreve um WAV mono de 16 bits.
//!
//! Uso:
//! ```sh
//! cargo run --release --example render_wav -- \
//!   <soundfont.sf2> <saida.wav> <nota-midi> <duracao-ms> [<nota-midi> ...]
//! ```
//! Cada nota toca 450 ms com 50 ms de silêncio (como a escala do `play.rs`);
//! uma nota só vira um áudio curto (o Sol da 2ª linha, um compasso contado).
//! A conversão para `.ogg` é com `ffmpeg`/`oggenc` no
//! `tool/build_course_media.sh`.

use std::fs::File;
use std::io::{Seek, SeekFrom, Write};
use std::sync::Arc;

use anyhow::{Context, Result};
use rustysynth::{SoundFont, Synthesizer, SynthesizerSettings};

const SAMPLE_RATE: i32 = 44100;
const NOTE_MS: u64 = 450;
const GAP_MS: u64 = 50;
const TAIL_MS: u64 = 400;

fn write_wav(path: &str, samples: &[i16]) -> Result<()> {
    let mut out = File::create(path).with_context(|| format!("criando {path}"))?;
    let data_bytes = (samples.len() * 2) as u32;
    // Cabeçalho WAV mono 16 bits, 44100 Hz.
    out.write_all(b"RIFF")?;
    out.write_all(&(36 + data_bytes).to_le_bytes())?;
    out.write_all(b"WAVEfmt ")?;
    out.write_all(&16u32.to_le_bytes())?;
    out.write_all(&1u16.to_le_bytes())?;
    out.write_all(&1u16.to_le_bytes())?;
    out.write_all(&(SAMPLE_RATE as u32).to_le_bytes())?;
    out.write_all(&((SAMPLE_RATE * 2) as u32).to_le_bytes())?;
    out.write_all(&2u16.to_le_bytes())?;
    out.write_all(&16u16.to_le_bytes())?;
    out.write_all(b"data")?;
    out.write_all(&data_bytes.to_le_bytes())?;
    for s in samples {
        out.write_all(&s.to_le_bytes())?;
    }
    out.flush()?;
    let _ = out.seek(SeekFrom::Start(0));
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let usage = "uso: render_wav <soundfont.sf2> <saida.wav> <nota-midi> <duracao-ms> [<nota-midi> ...]";
    let sf2_path = args.next().context(usage)?;
    let out_path = args.next().context(usage)?;
    let midi_note: i32 = args.next().context(usage)?.parse().context("nota-midi")?;
    let duration_ms: u64 = args.next().context(usage)?.parse().context("duracao-ms")?;
    let extra: Vec<i32> = args
        .map(|a| a.parse::<i32>().context("nota-midi extra"))
        .collect::<Result<_>>()?;

    let mut keys = vec![midi_note];
    keys.extend(extra);

    let sound_font = Arc::new(
        SoundFont::new(&mut File::open(&sf2_path).with_context(|| format!("abrindo {sf2_path}"))?)
            .with_context(|| format!("lendo soundfont {sf2_path}"))?,
    );
    let settings = SynthesizerSettings::new(SAMPLE_RATE);
    let mut synth = Synthesizer::new(&sound_font, &settings).context("criando o sintetizador")?;

    // Agenda: cada nota dura NOTE_MS (ou duration_ms na última, para o
    // compasso contado ser mais curto/longo), com GAP_MS entre elas.
    let note_frames = (NOTE_MS as f64 * SAMPLE_RATE as f64 / 1000.0).round() as usize;
    let gap_frames = (GAP_MS as f64 * SAMPLE_RATE as f64 / 1000.0).round() as usize;
    let last_frames = (duration_ms as f64 * SAMPLE_RATE as f64 / 1000.0).round() as usize;
    let tail_frames = (TAIL_MS as f64 * SAMPLE_RATE as f64 / 1000.0).round() as usize;
    let total = keys.len() * (note_frames + gap_frames) + last_frames + tail_frames;

    let mut left = vec![0f32; 1024];
    let mut right = vec![0f32; 1024];
    let mut mono: Vec<f32> = Vec::with_capacity(total);

    // Toca as notas em sequência, renderizando em blocos.
    let mut rendered = 0usize;
    for (i, &key) in keys.iter().enumerate() {
        synth.note_on(0, key, 100);
        let want = if i + 1 == keys.len() {
            last_frames
        } else {
            note_frames
        };
        let mut done = 0usize;
        while done < want {
            let n = (want - done).min(1024);
            synth.render(&mut left[..n], &mut right[..n]);
            for k in 0..n {
                mono.push((left[k] + right[k]) * 0.5);
            }
            done += n;
            rendered += n;
        }
        synth.note_off(0, key);
        let mut gap = 0usize;
        while gap < gap_frames {
            let n = (gap_frames - gap).min(1024);
            synth.render(&mut left[..n], &mut right[..n]);
            for k in 0..n {
                mono.push((left[k] + right[k]) * 0.5);
            }
            gap += n;
            rendered += n;
        }
    }
    // Cauda para o release não cortar.
    let mut tail = 0usize;
    while tail < tail_frames {
        let n = (tail_frames - tail).min(1024);
        synth.render(&mut left[..n], &mut right[..n]);
        for k in 0..n {
            mono.push((left[k] + right[k]) * 0.5);
        }
        tail += n;
        rendered += n;
    }
    let _ = rendered;

    let peak = mono.iter().map(|v| v.abs()).fold(0f32, f32::max).max(1e-6);
    let gain = (0.89 / peak).min(4.0);
    let samples: Vec<i16> = mono
        .iter()
        .map(|v| ((v * gain).clamp(-1.0, 1.0) * 32767.0).round() as i16)
        .collect();
    write_wav(&out_path, &samples)?;
    println!("gravado {out_path} ({} amostras, pico {:.2})", samples.len(), peak * gain);
    Ok(())
}
