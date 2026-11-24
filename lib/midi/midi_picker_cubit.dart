// A busca do diálogo "Teclado MIDI" (M01) em BLoC. O diálogo é que o cria
// (com `BlocProvider`) e o fecha; a busca que ainda termina depois de o
// diálogo fechar não mexe mais no estado.

import 'package:zywny_bloc/zywny_bloc.dart';

/// Só se a busca corre: o botão de procurar gira enquanto ela corre.
class MidiPickerState extends Equatable {
  const MidiPickerState({this.searching = false});

  /// A busca (o "Procurar de novo", ou o pedido de permissão) está correndo.
  final bool searching;

  MidiPickerState copyWith({bool? searching}) =>
      MidiPickerState(searching: searching ?? this.searching);

  @override
  List<Object?> get props => [searching];
}

/// Procura os teclados pelo botão do diálogo. [buscar] é o que procura (no
/// Android, o Bluetooth; no resto, relê a lista); os testes trocam por um
/// falso.
class MidiPickerCubit extends Cubit<MidiPickerState> {
  MidiPickerCubit({required this.buscar}) : super(const MidiPickerState());

  final Future<void> Function() buscar;

  /// Procura de novo: liga a busca, espera [buscar] e desliga, mesmo se ele
  /// falhar (o erro segue para quem chamou).
  Future<void> search() async {
    emit(state.copyWith(searching: true));
    try {
      await buscar();
    } finally {
      if (!isClosed) emit(state.copyWith(searching: false));
    }
  }
}
