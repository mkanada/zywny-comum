// O Monitor MIDI (M01) em BLoC: as últimas mensagens que chegam de um teclado.
// A entrada é o `Stream` de notas do teclado (fluxo, não estado): o Cubit o
// escuta e guarda só a lista que a tela mostra. Quem cancela a escuta é o
// `close()`, antes do `super.close()`.

import 'dart:async';

import 'package:zywny_bloc/zywny_bloc.dart';
import 'package:zywny_midi/midi_input_service.dart';

/// As mensagens que o monitor guarda: a mais recente primeiro.
class MidiMonitorState extends Equatable {
  const MidiMonitorState({this.messages = const []});

  /// As últimas notas recebidas, a mais nova na frente; no máximo o limite do Cubit.
  final List<PlayedNote> messages;

  MidiMonitorState copyWith({List<PlayedNote>? messages}) =>
      MidiMonitorState(messages: messages ?? this.messages);

  @override
  List<Object?> get props => [messages];
}

/// Escuta as notas de um teclado e guarda as últimas [limite] (M01).
class MidiMonitorCubit extends Cubit<MidiMonitorState> {
  MidiMonitorCubit({required Stream<PlayedNote> notes, required this.limite})
    : super(const MidiMonitorState()) {
    _assinatura = notes.listen(_chegou);
  }

  /// Quantas mensagens ficam; a mais antiga sai quando passa dele.
  final int limite;

  StreamSubscription<PlayedNote>? _assinatura;

  void _chegou(PlayedNote nota) {
    emit(
      state.copyWith(messages: [nota, ...state.messages].take(limite).toList()),
    );
  }

  @override
  Future<void> close() {
    _assinatura?.cancel();
    return super.close();
  }
}
