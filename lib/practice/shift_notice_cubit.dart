// O aviso da faixa no topo da partitura (Q07): o do detector de
// deslocamento e o lembrete de voltar o TRANSPOSE a 0. Quem põe o aviso é o
// dono deste Cubit (a tela da partitura); a faixa (`ShiftBanner`) o lê e o
// fecha por ele, sem notificador de valor (BL33).

import 'package:zywny_bloc/zywny_bloc.dart';

import 'shift_detector.dart';

/// O aviso que a faixa mostra agora (`null`: nenhum).
class ShiftNoticeState extends Equatable {
  const ShiftNoticeState({this.notice});

  final ShiftNotice? notice;

  @override
  List<Object?> get props => [notice];
}

/// Mostra e fecha o aviso da faixa.
class ShiftNoticeCubit extends Cubit<ShiftNoticeState> {
  ShiftNoticeCubit() : super(const ShiftNoticeState());

  /// Mostra [notice]. O mesmo aviso, ou fechar sem aviso, não avisa de novo
  /// (o `emit` do BLoC deixa passar o primeiro estado mesmo que seja igual).
  void show(ShiftNotice notice) {
    if (notice == state.notice) return;
    emit(ShiftNoticeState(notice: notice));
  }

  /// Fecha o aviso (a faixa chama isto quando some ou quando é tocada).
  void clear() {
    if (state.notice == null) return;
    emit(const ShiftNoticeState());
  }
}
