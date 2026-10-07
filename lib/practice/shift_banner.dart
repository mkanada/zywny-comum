// Q07: a faixa no topo da partitura com o aviso do TRANSPOSE (docs/plano/Q07).
import 'dart:async';

import 'package:flutter/material.dart';

import '../midi/midi_input_service.dart';
import 'shift_detector.dart';

/// Quanto tempo a faixa fica na tela sozinha.
const Duration kShiftBannerDuration = Duration(seconds: 8);

/// A faixa: mostra o aviso de [notice] e some em [duration] ou, se o aviso
/// pede ([ShiftNotice.hideOnPlay]), quando [notes] entrega a próxima nota
/// tocada. Tocar na faixa também a fecha. Ao sumir, zera [notice].
class ShiftBanner extends StatefulWidget {
  const ShiftBanner({
    super.key,
    required this.notice,
    required this.notes,
    this.duration = kShiftBannerDuration,
  });

  final ValueNotifier<ShiftNotice?> notice;
  final Stream<PlayedNote> notes;
  final Duration duration;

  @override
  State<ShiftBanner> createState() => _ShiftBannerState();
}

class _ShiftBannerState extends State<ShiftBanner> {
  Timer? _timer;
  ShiftNotice? _shown;
  late StreamSubscription<PlayedNote> _sub;

  /// A nota que fez o aviso nascer chega a esta faixa na mesma entrega (o
  /// treino a recebeu primeiro): só vale como "tocou de novo" a que vier
  /// depois.
  var _listening = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.notes.listen(_onNote);
    widget.notice.addListener(_onNotice);
    _shown = widget.notice.value;
    _arm();
    _listening = true;
  }

  @override
  void didUpdateWidget(ShiftBanner old) {
    super.didUpdateWidget(old);
    if (old.notice != widget.notice) {
      old.notice.removeListener(_onNotice);
      widget.notice.addListener(_onNotice);
      _onNotice();
    }
    if (old.notes != widget.notes) {
      unawaited(_sub.cancel());
      _sub = widget.notes.listen(_onNote);
    }
  }

  @override
  void dispose() {
    widget.notice.removeListener(_onNotice);
    unawaited(_sub.cancel());
    _timer?.cancel();
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    _timer = _shown == null ? null : Timer(widget.duration, _dismiss);
  }

  void _onNotice() {
    final notice = widget.notice.value;
    if (notice == _shown) return;
    setState(() => _shown = notice);
    _arm();
    _listening = false;
    scheduleMicrotask(() => _listening = true);
  }

  void _onNote(PlayedNote note) {
    if (_listening && note.on && (_shown?.hideOnPlay ?? false)) _dismiss();
  }

  void _dismiss() => widget.notice.value = null;

  @override
  Widget build(BuildContext context) {
    final notice = _shown;
    if (notice == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            key: const ValueKey('shift-banner'),
            color: scheme.inverseSurface,
            elevation: 3,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _dismiss,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Text(
                  notice.message,
                  style: TextStyle(
                    color: scheme.onInverseSurface,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
