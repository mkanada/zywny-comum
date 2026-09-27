#!/usr/bin/env python3
"""Teclado MIDI falso no ALSA sequencer, sem dependências (ctypes + libasound).

Cria um cliente "Zywny Fake Keyboard" com uma porta tipo HARDWARE — o filtro
de enumeração do flutter_midi_command_linux exige esse bit — e toca uma
escala (ou as notas passadas na linha de comando) para os assinantes.

  python3 fake_midi_keyboard.py                 # escala de dó, em laço
  python3 fake_midi_keyboard.py 60 64 67 --once # arpejo uma vez
  python3 fake_midi_keyboard.py --list          # lista portas com tipo/capacidade
  python3 fake_midi_keyboard.py --relay         # repassa o que chegar na porta
                                                # (ex.: aconnect VMPK -> esta porta)
"""
import ctypes as C
import sys
import time

asound = C.CDLL("libasound.so.2")

SND_SEQ_OPEN_DUPLEX = 3
CAP_READ, CAP_WRITE, CAP_SUBS_READ, CAP_SUBS_WRITE = 1 << 0, 1 << 1, 1 << 5, 1 << 6
TYPE_MIDI_GENERIC, TYPE_HARDWARE, TYPE_SOFTWARE, TYPE_APPLICATION, TYPE_PORT = (
    1 << 1, 1 << 16, 1 << 17, 1 << 20, 1 << 19)
EV_NOTEON, EV_NOTEOFF = 6, 7
SUBS, DIRECT = 254, 253  # SND_SEQ_ADDRESS_SUBSCRIBERS, SND_SEQ_QUEUE_DIRECT


class Addr(C.Structure):
    _fields_ = [("client", C.c_ubyte), ("port", C.c_ubyte)]


class Note(C.Structure):
    _fields_ = [("channel", C.c_ubyte), ("note", C.c_ubyte), ("velocity", C.c_ubyte),
                ("off_velocity", C.c_ubyte), ("duration", C.c_uint)]


class Data(C.Union):
    _fields_ = [("note", Note), ("raw", C.c_ubyte * 12)]


class Event(C.Structure):  # snd_seq_event_t (28 bytes)
    _fields_ = [("type", C.c_ubyte), ("flags", C.c_ubyte), ("tag", C.c_char),
                ("queue", C.c_ubyte), ("time", C.c_uint * 2), ("source", Addr),
                ("dest", Addr), ("data", Data)]


def open_seq(name):
    seq = C.c_void_p()
    if asound.snd_seq_open(C.byref(seq), b"default", SND_SEQ_OPEN_DUPLEX, 0) < 0:
        sys.exit("não abriu o sequencer (módulo snd_seq carregado?)")
    asound.snd_seq_set_client_name(seq, name)
    return seq


def list_ports():
    seq = open_seq(b"zywny-lister")
    ci, pi = C.c_void_p(), C.c_void_p()
    asound.snd_seq_client_info_malloc(C.byref(ci))
    asound.snd_seq_port_info_malloc(C.byref(pi))
    asound.snd_seq_port_info_get_name.restype = C.c_char_p
    asound.snd_seq_client_info_get_name.restype = C.c_char_p
    asound.snd_seq_client_info_set_client(ci, -1)
    while asound.snd_seq_query_next_client(seq, ci) >= 0:
        c = asound.snd_seq_client_info_get_client(ci)
        asound.snd_seq_port_info_set_client(pi, c)
        asound.snd_seq_port_info_set_port(pi, -1)
        while asound.snd_seq_query_next_port(seq, pi) >= 0:
            t = asound.snd_seq_port_info_get_type(pi)
            cap = asound.snd_seq_port_info_get_capability(pi)
            ok_in = (cap & CAP_READ) and (cap & CAP_SUBS_READ)
            seen = bool(t & TYPE_HARDWARE) and ok_in and c not in (0, 14)
            print(f"{c:3}:{asound.snd_seq_port_info_get_port(pi):<2} "
                  f"{asound.snd_seq_client_info_get_name(ci).decode():<22} "
                  f"{asound.snd_seq_port_info_get_name(pi).decode():<24} "
                  f"type=0x{t:06x} HW={'s' if t & TYPE_HARDWARE else 'n'} "
                  f"-> plugin vê como entrada: {'SIM' if seen else 'não'}")


def open_fake_port():
    seq = open_seq(b"Zywny Fake Keyboard")
    port = asound.snd_seq_create_simple_port(
        seq, b"Fake Keys", CAP_READ | CAP_SUBS_READ | CAP_WRITE | CAP_SUBS_WRITE,
        TYPE_MIDI_GENERIC | TYPE_HARDWARE | TYPE_PORT)
    me = asound.snd_seq_client_id(seq)
    print(f"porta {me}:{port} pronta — conecte com: aseqdump -p {me}:{port}", flush=True)
    return seq, me, port


def relay():
    """Reenvia aos assinantes todo evento que chega na porta: um teclado de
    software (VMPK etc.) ligado com `aconnect <vmpk> <esta porta>` passa a
    aparecer para o app como hardware — com pedal, CC e tudo."""
    seq, me, port = open_fake_port()
    print(f"ligue a fonte com: aconnect <cliente>:<porta> {me}:{port}", flush=True)
    evp = C.POINTER(Event)()
    while True:
        if asound.snd_seq_event_input(seq, C.byref(evp)) < 0:
            continue
        ev = evp.contents
        if ev.source.client == 0:  # anúncios do System (subscribe/unsubscribe)
            continue
        ev.source, ev.dest, ev.queue = Addr(me, port), Addr(SUBS, 0), DIRECT
        asound.snd_seq_event_output_direct(seq, evp)


def play(notes, once, vel=90, dur=0.25, gap=0.15):
    seq, me, port = open_fake_port()
    time.sleep(1.0)

    def send(kind, n, v):
        ev = Event(type=kind, queue=DIRECT, source=Addr(me, port), dest=Addr(SUBS, 0))
        ev.data.note = Note(0, n, v, 0, 0)
        asound.snd_seq_event_output_direct(seq, C.byref(ev))

    while True:
        for n in notes:
            send(EV_NOTEON, n, vel)
            time.sleep(dur)
            send(EV_NOTEOFF, n, 0)
            time.sleep(gap)
        if once:
            break
        time.sleep(1.0)


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--list" in args:
        list_ports()
    elif "--relay" in args:
        relay()
    else:
        nums = [int(a) for a in args if a.isdigit()] or [60, 62, 64, 65, 67, 69, 71, 72]
        play(nums, "--once" in args)
