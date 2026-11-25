// Q07: a faixa no topo da partitura com o aviso do TRANSPOSE (docs/plano/Q07).
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_midi/midi_input_service.dart';

import 'shift_detector.dart';
import 'shift_notice_cubit.dart';

/// Quanto tempo a faixa fica na tela sozinha.
const Duration kShiftBannerDuration = Duration(seconds: 8);

/// A faixa: mostra o aviso de [notice] e some em [duration] ou, se o aviso
/// pede ([ShiftNotice.hideOnPlay]), quando [notes] entrega a próxima nota
/// tocada. Tocar na faixa também a fecha. Ao sumir, zera o aviso em [notice].
class ShiftBanner extends StatelessWidget {
  const ShiftBanner({
    super.key,
    required this.notice,
    required this.notes,
    this.duration = kShiftBannerDuration,
  });

  /// O Cubit que guarda o aviso: a faixa o lê e o fecha; quem o mostra é o dono.
  final ShiftNoticeCubit notice;
  final Stream<PlayedNote> notes;
  final Duration duration;

  @override
  Widget build(BuildContext context) => BlocProvider(
    // Outro aviso, outras notas ou outro prazo: refaz o Cubit, que assina as
    // duas coisas na criação.
    key: ValueKey((notice, notes, duration)),
    create: (_) => ShiftBannerCubit(
      notice: notice,
      notes: notes,
      duration: duration,
    ),
    child: const _ShiftBannerView(),
  );
}

/// O aviso que a faixa mostra agora (`null` se ela está fechada).
class ShiftBannerState extends Equatable {
  const ShiftBannerState({this.shown});

  final ShiftNotice? shown;

  @override
  List<Object?> get props => [shown];
}

/// A faixa por dentro: copia o aviso do [notice] para o estado, arma o prazo
/// de sumir e fecha quando a próxima nota chega (se o aviso pede). O
/// [close] tira a escuta do aviso, cancela o prazo e a escuta das notas.
class ShiftBannerCubit extends Cubit<ShiftBannerState> {
  ShiftBannerCubit({
    required ShiftNoticeCubit notice,
    required Stream<PlayedNote> notes,
    required this.duration,
  }) : _notice = notice,
       super(ShiftBannerState(shown: notice.state.notice)) {
    _sub = notes.listen(_aoTocar);
    _avisoSub = notice.stream.listen(_aoAviso);
    _armar();
    _ouvindo = true;
  }

  /// Dono do aviso: a faixa só o lê, e fechar passa por ele.
  final ShiftNoticeCubit _notice;
  final Duration duration;
  late final StreamSubscription<PlayedNote> _sub;
  late final StreamSubscription<ShiftNoticeState> _avisoSub;
  Timer? _prazo;

  /// A nota que fez o aviso nascer chega a esta faixa na mesma entrega (o
  /// treino a recebeu primeiro): só vale como "tocou de novo" a que vier
  /// depois.
  var _ouvindo = false;

  /// Fecha a faixa (e zera o aviso, para quem o ouve).
  void fechar() => _notice.clear();

  void _armar() {
    _prazo?.cancel();
    _prazo = state.shown == null ? null : Timer(duration, fechar);
  }

  void _aoAviso(ShiftNoticeState estado) {
    final notice = estado.notice;
    if (notice == state.shown) return;
    emit(ShiftBannerState(shown: notice));
    _armar();
    _ouvindo = false;
    scheduleMicrotask(() => _ouvindo = true);
  }

  void _aoTocar(PlayedNote note) {
    if (_ouvindo && note.on && (state.shown?.hideOnPlay ?? false)) fechar();
  }

  @override
  Future<void> close() {
    unawaited(_avisoSub.cancel());
    unawaited(_sub.cancel());
    _prazo?.cancel();
    return super.close();
  }
}

class _ShiftBannerView extends StatelessWidget {
  const _ShiftBannerView();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ShiftBannerCubit, ShiftBannerState, ShiftNotice?>(
      selector: (state) => state.shown,
      builder: (context, notice) {
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
                  onTap: context.read<ShiftBannerCubit>().fechar,
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
      },
    );
  }
}
