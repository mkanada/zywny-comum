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

thread_local! {
    static LAST_PANIC: RefCell<String> = const { RefCell::new(String::new()) };
}

/// Guarda mensagem + local de cada panic desta thread: o payload de um
/// `catch_unwind` nem sempre é `&str`/`String` (e o stderr não chega ao
/// logcat no Android), então o hook é a fonte confiável do texto.
fn install_panic_hook() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            LAST_PANIC.with(|slot| *slot.borrow_mut() = info.to_string());
            previous(info);
        }));
    });
}

fn panic_message(_payload: &(dyn std::any::Any + Send)) -> String {
    LAST_PANIC.with(|slot| slot.borrow().clone())
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
    install_panic_hook();
    match catch_unwind(|| ZyEngine::new(preferred_buffer_frames)) {
        Ok(Ok(engine)) => Box::into_raw(Box::new(engine)),
        Ok(Err(e)) => {
            set_last_error(e);
            ptr::null_mut()
        }
        Err(p) => {
            set_last_error(format!("panic em zy_engine_new: {}", panic_message(&p)));
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
    install_panic_hook();
    let engine = &mut *engine;
    let slice = slice::from_raw_parts(bytes, len);
    match catch_unwind(AssertUnwindSafe(|| engine.load_sf2(slice))) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            set_last_error(e);
            -1
        }
        Err(p) => {
            set_last_error(format!("panic em zy_engine_load_sf2: {}", panic_message(&p)));
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

/// Android: o `cpal` (via `ndk-context`) precisa da `JavaVM` e de um
/// `Context` para falar com o `AudioManager`, e o Flutter não inicializa
/// isso. `MainActivity.onCreate` chama este método (JNI) antes de qualquer
/// `zy_engine_new`. Tabela JNI usada à mão (NewGlobalRef = 21, GetJavaVM =
/// 219) para não puxar o crate `jni` como dependência direta.
#[cfg(target_os = "android")]
#[no_mangle]
pub unsafe extern "system" fn Java_com_example_zywny_MainActivity_nativeInit(
    env: *mut *const *const std::ffi::c_void,
    _this: *mut std::ffi::c_void,
    context: *mut std::ffi::c_void,
) {
    use std::ffi::c_void;
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        type GetJavaVm = unsafe extern "system" fn(*mut *const *const c_void, *mut *mut c_void) -> i32;
        type NewGlobalRef =
            unsafe extern "system" fn(*mut *const *const c_void, *mut c_void) -> *mut c_void;
        let table = *env;
        let get_java_vm: GetJavaVm = std::mem::transmute(*table.add(219));
        let new_global_ref: NewGlobalRef = std::mem::transmute(*table.add(21));
        let mut vm: *mut c_void = ptr::null_mut();
        if get_java_vm(env, &mut vm) != 0 || vm.is_null() {
            return;
        }
        let global = new_global_ref(env, context);
        ndk_context::initialize_android_context(vm, global);
    });
}
