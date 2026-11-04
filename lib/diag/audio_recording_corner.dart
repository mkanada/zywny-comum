import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio_recording_service.dart';

/// Quanto tempo segurar o canto para ligar/desligar a gravação.
const Duration kAudioRecordingHold = Duration(seconds: 1);

/// Lado do canto sensível, em dp.
const double kAudioRecordingCorner = 72;

/// Gravação de áudio do microfone, a qualquer hora e em qualquer tela
/// (modo depuração): segurar o canto inferior esquerdo por [kAudioRecordingHold]
/// liga; segurar de novo desliga e guarda o `.wav`.
///
/// Fica por cima da tela sem tomar os toques: o que está embaixo do canto
/// continua recebendo-os. Enquanto grava, um ponto vermelho com o tempo fica
/// à vista, também sem tomar toque.
class AudioRecordingCorner extends StatefulWidget {
  const AudioRecordingCorner({super.key, this.service});

  /// Os testes passam um falso; sem ele, cria o da plataforma ao primeiro uso.
  final AudioRecordingService? service;

  @override
  State<AudioRecordingCorner> createState() => AudioRecordingCornerState();
}

class AudioRecordingCornerState extends State<AudioRecordingCorner> {
  AudioRecordingService? _service;
  Timer? _hold;
  Timer? _tick;
  Timer? _noticeTimer;
  int? _pointer;
  Offset _origin = Offset.zero;
  bool _busy = false;
  bool _recording = false;
  DateTime? _since;
  String? _notice;

  bool get recording => _recording;

  AudioRecordingService get _svc =>
      _service ??= widget.service ?? createAudioRecordingService();

  @override
  void dispose() {
    _hold?.cancel();
    _tick?.cancel();
    _noticeTimer?.cancel();
    final service = _service;
    if (service != null) unawaited(service.dispose());
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _origin = e.position;
    _hold?.cancel();
    _hold = Timer(kAudioRecordingHold, () => unawaited(toggle()));
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer == _pointer && (e.position - _origin).distance > 24) {
      _cancel();
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer == _pointer) _cancel();
  }

  void _cancel() {
    _pointer = null;
    _hold?.cancel();
    _hold = null;
  }

  Future<void> toggle() async {
    if (_busy) return;
    _busy = true;
    try {
      unawaited(HapticFeedback.heavyImpact());
      if (_recording) {
        final result = await _svc.stop();
        _tick?.cancel();
        if (!mounted) return;
        setState(() => _recording = false);
        _showNotice(
          result?.savedAt == null
              ? 'Gravação não salva'
              : 'Gravação salva: ${result!.savedAt}',
          const Duration(seconds: 6),
        );
      } else {
        final ok = await _svc.start();
        if (!mounted) return;
        if (!ok) {
          _showNotice(
            'Não deu para gravar (microfone ou permissão)',
            const Duration(seconds: 4),
          );
          return;
        }
        _since = DateTime.now();
        _tick = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
        setState(() {
          _recording = true;
          _notice = null;
        });
      }
    } finally {
      _busy = false;
    }
  }

  void _showNotice(String text, Duration time) {
    _noticeTimer?.cancel();
    setState(() => _notice = text);
    _noticeTimer = Timer(time, () {
      if (mounted) setState(() => _notice = null);
    });
  }

  String _elapsed() {
    final s = DateTime.now().difference(_since ?? DateTime.now()).inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          bottom: 0,
          width: kAudioRecordingCorner,
          height: kAudioRecordingCorner,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
          ),
        ),
        if (_recording || _notice != null)
          Positioned(
            left: 8,
            bottom: 8,
            child: IgnorePointer(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_recording) ...[
                          const Icon(
                            Icons.fiber_manual_record,
                            color: Color(0xFFFF3B30),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          _recording ? 'Gravando ${_elapsed()}' : _notice!,
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 12,
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
