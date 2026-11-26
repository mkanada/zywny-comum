// A splash que cobre o app: o Cubit guarda se ela ainda cobre e a desliga
// depois de um tempo. O timer (do relógio do app) para no close(), então uma
// tela que sai antes do fim não recebe o aviso.

import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_clock/zywny_clock.dart';

/// Se a splash ainda cobre o app.
class SplashState extends Equatable {
  const SplashState({required this.showing});

  /// `true` até o tempo passar; depois, o fade leva a splash embora.
  final bool showing;

  SplashState copyWith({bool? showing}) =>
      SplashState(showing: showing ?? this.showing);

  @override
  List<Object?> get props => [showing];
}

/// Começa cobrindo o app e some depois de [duration] (ver `SplashOverlay`). O
/// tempo é o do [clock] recebido.
class SplashCubit extends Cubit<SplashState> {
  SplashCubit({required Duration duration, required AppClock clock})
    : super(const SplashState(showing: true)) {
    _timer = clock.timer(duration, hide);
  }

  AppTimer? _timer;

  /// Tira a splash de cima do app (o fim do tempo chama isto).
  void hide() {
    if (isClosed) return;
    emit(state.copyWith(showing: false));
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
