//! `zywny_audio` — pilha de som nativa do zywny: `rustysynth` (síntese SF2)
//! + `cpal` (saída de áudio).
//!
//! K01 provou a pilha com um protótipo em CLI (`examples/play.rs`, ainda
//! aqui). K02 (este crate agora) move a lógica para uma biblioteca de
//! verdade: [engine] é o motor propriamente dito (estado, agenda por
//! amostra, relógio); [ffi] expõe uma API C (`#[no_mangle]`) mínima e
//! segura para o Dart chamar por `dart:ffi` (K03) — ver
//! `include/zywny_audio.h`.

pub mod engine;
mod ffi;

pub use engine::{RawMidi, Stat, ZyEngine, DEFAULT_BUFFER_FRAMES};
pub use ffi::{zy_last_error, ZyEvent};
