//! API C do motor (K02): superfície mínima para o Dart chamar por
//! `dart:ffi` — ver `include/zywny_audio.h`. `zy_engine_new`/
//! `zy_engine_load_sf2` fazem trabalho de verdade (abrir dispositivo, ler
//! bytes de SF2) e por isso capturam panics (`catch_unwind`); as demais só
//! leem/escrevem estado simples (atômicos, ou empurram um comando numa
//! fila) e não deveriam panicar — `ZyEngine::push_command` já recupera de
//! um `Mutex` envenenado em vez de propagar.

use std::cell::RefCell;
use std::ffi::CString;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use crate::engine::{RawMidi, Stat, ZyEngine};

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

fn set_last_error(msg: impl std::fmt::Display) {
    let text = msg.to_string();
    let c = CString::new(text).unwrap_or_else(|_| {
        CString::new("erro (mensagem continha um byte nulo)").expect("string literal sem nulos")
    });
    LAST_ERROR.with(|slot| *slot.borrow_mut() = Some(c));
}

/// Mensagem do último erro nesta thread, válida até a próxima chamada FFI
/// que falhe nesta mesma thread (ou até a thread acabar). `NULL` se ainda
/// não houve erro nesta thread.
#[no_mangle]
pub extern "C" fn zy_last_error() -> *const c_char {
    LAST_ERROR.with(|slot| slot.borrow().as_ref().map_or(ptr::null(), |c| c.as_ptr()))
}

/// Espelha `ZyEvent` do header C (`frame` + 3 bytes MIDI + 1 de padding
/// explícito).
#[repr(C)]
pub struct ZyEvent {
    pub frame: u64,
    pub status: u8,
    pub d1: u8,
    pub d2: u8,
    pub _pad: u8,
}

/// `NULL` em erro — a mensagem fica em [zy_last_error].
#[no_mangle]
pub extern "C" fn zy_engine_new(preferred_buffer_frames: i32) -> *mut ZyEngine {
    match catch_unwind(|| ZyEngine::new(preferred_buffer_frames)) {
        Ok(Ok(engine)) => Box::into_raw(Box::new(engine)),
        Ok(Err(e)) => {
            set_last_error(e);
            ptr::null_mut()
        }
        Err(_) => {
            set_last_error("panic em zy_engine_new");
            ptr::null_mut()
        }
    }
}

/// 0 em sucesso, -1 em erro (mensagem em [zy_last_error]).
///
/// # Safety
/// `engine` deve ser um ponteiro devolvido por [zy_engine_new] e ainda não
/// liberado por [zy_engine_free]; `bytes` deve apontar para (pelo menos)
/// `len` bytes válidos.
#[no_mangle]
pub unsafe extern "C" fn zy_engine_load_sf2(
    engine: *mut ZyEngine,
    bytes: *const u8,
    len: usize,
) -> i32 {
    if engine.is_null() || bytes.is_null() {
        set_last_error("ponteiro nulo");
        return -1;
    }
    let engine = &mut *engine;
    let slice = slice::from_raw_parts(bytes, len);
    match catch_unwind(AssertUnwindSafe(|| engine.load_sf2(slice))) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            set_last_error(e);
            -1
        }
        Err(_) => {
            set_last_error("panic em zy_engine_load_sf2");
            -1
        }
    }
}

/// # Safety
/// `engine` deve ser um ponteiro devolvido por [zy_engine_new] (ou `NULL`,
/// que é um no-op), não usado depois desta chamada.
#[no_mangle]
pub unsafe extern "C" fn zy_engine_free(engine: *mut ZyEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

/// # Safety
/// `engine` deve ser `NULL` ou um ponteiro válido devolvido por
/// [zy_engine_new].
#[no_mangle]
pub unsafe extern "C" fn zy_sample_rate(engine: *const ZyEngine) -> i32 {
    if engine.is_null() {
        return 0;
    }
    (*engine).sample_rate()
}

/// # Safety
/// Idem [zy_sample_rate].
#[no_mangle]
pub unsafe extern "C" fn zy_output_latency_frames(engine: *const ZyEngine) -> i32 {
    if engine.is_null() {
        return 0;
    }
    (*engine).output_latency_frames()
}

/// # Safety
/// Idem [zy_sample_rate].
#[no_mangle]
pub unsafe extern "C" fn zy_now_frame(engine: *const ZyEngine) -> u64 {
    if engine.is_null() {
        return 0;
    }
    (*engine).now_frame()
}

/// # Safety
/// Idem [zy_sample_rate].
#[no_mangle]
pub unsafe extern "C" fn zy_render_frame(engine: *const ZyEngine) -> u64 {
    if engine.is_null() {
        return 0;
    }
    (*engine).render_frame()
}

/// # Safety
/// Idem [zy_sample_rate].
#[no_mangle]
pub unsafe extern "C" fn zy_send(engine: *const ZyEngine, status: u8, d1: u8, d2: u8) {
    if !engine.is_null() {
        (*engine).send(status, d1, d2);
    }
}

/// # Safety
/// `engine` como acima; `events` deve apontar para (pelo menos) `n`
/// `ZyEvent`s válidos.
#[no_mangle]
pub unsafe extern "C" fn zy_schedule(engine: *const ZyEngine, events: *const ZyEvent, n: usize) {
    if engine.is_null() || events.is_null() {
        return;
    }
    let engine = &*engine;
    let events = slice::from_raw_parts(events, n);
    let batch: Vec<(u64, RawMidi)> = events
        .iter()
        .map(|e| (e.frame, [e.status, e.d1, e.d2]))
        .collect();
    engine.schedule(&batch);
}

/// # Safety
/// Idem [zy_sample_rate].
#[no_mangle]
pub unsafe extern "C" fn zy_clear_scheduled(engine: *const ZyEngine) {
    if !engine.is_null() {
        (*engine).clear_scheduled();
    }
}

/// # Safety
/// Idem [zy_sample_rate].
#[no_mangle]
pub unsafe extern "C" fn zy_all_notes_off(engine: *const ZyEngine) {
    if !engine.is_null() {
        (*engine).all_notes_off();
    }
}

/// # Safety
/// Idem [zy_sample_rate].
#[no_mangle]
pub unsafe extern "C" fn zy_set_gain(engine: *const ZyEngine, gain: f32) {
    if !engine.is_null() {
        (*engine).set_gain(gain);
    }
}

/// `which`: `ZY_STAT_UNDERRUNS` (0) ou `ZY_STAT_DROPPED_EVENTS` (1) — outro
/// valor devolve 0.
///
/// # Safety
/// Idem [zy_sample_rate].
#[no_mangle]
pub unsafe extern "C" fn zy_stat(engine: *const ZyEngine, which: i32) -> u64 {
    if engine.is_null() {
        return 0;
    }
    let stat = match which {
        0 => Stat::Underruns,
        1 => Stat::DroppedEvents,
        _ => return 0,
    };
    (*engine).stat(stat)
}
