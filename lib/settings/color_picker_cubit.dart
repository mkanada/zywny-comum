// Estado do seletor de cor (color_picker.dart): a cor escolhida, o ajuste
// fino (matiz, saturação e brilho) e um contador que sobe a cada escolha pela
// paleta ou pelo ajuste, para o campo do código acompanhar mesmo quando a cor
// já era aquela.

import 'package:flutter/material.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

/// A cor do seletor, o ajuste fino e o contador de escolhas.
class ColorPickerState extends Equatable {
  const ColorPickerState({
    required this.color,
    required this.hsv,
    this.serial = 0,
  });

  /// A cor que o seletor mostra e que "Aplicar" devolve (sempre opaca).
  final Color color;

  /// Guardado à parte de [color]: no cinza (saturação 0) ou no preto a cor não
  /// diz mais o matiz, e os controles pulariam para o vermelho.
  final HSVColor hsv;

  /// Sobe a cada escolha pela paleta ou pelo ajuste fino. O código digitado não
  /// sobe: quem digita já vê o próprio texto no campo.
  final int serial;

  ColorPickerState copyWith({Color? color, HSVColor? hsv, int? serial}) =>
      ColorPickerState(
        color: color ?? this.color,
        hsv: hsv ?? this.hsv,
        serial: serial ?? this.serial,
      );

  @override
  List<Object?> get props => [color, hsv, serial];
}

/// O seletor de cor: a paleta, o ajuste fino e o código digitado mudam a cor
/// deste estado.
class ColorPickerCubit extends Cubit<ColorPickerState> {
  ColorPickerCubit({required Color initial}) : super(_inicial(initial));

  static ColorPickerState _inicial(Color initial) {
    final cor = initial.withAlpha(0xFF);
    return ColorPickerState(color: cor, hsv: HSVColor.fromColor(cor));
  }

  /// Escolhe uma cor da paleta (ou a "Padrão").
  void escolher(Color color) {
    final cor = color.withAlpha(0xFF);
    emit(
      ColorPickerState(
        color: cor,
        hsv: HSVColor.fromColor(cor),
        serial: state.serial + 1,
      ),
    );
  }

  /// Mexe num dos controles deslizantes (matiz, saturação ou brilho).
  void ajustar(HSVColor hsv) {
    emit(
      state.copyWith(color: hsv.toColor(), hsv: hsv, serial: state.serial + 1),
    );
  }

  /// O código digitado: só vale com seis dígitos hexadecimais; senão, nada
  /// muda.
  void digitar(String text) {
    if (text.length != 6) return;
    final rgb = int.tryParse(text, radix: 16);
    if (rgb == null) return;
    final cor = Color(0xFF000000 | rgb);
    emit(state.copyWith(color: cor, hsv: HSVColor.fromColor(cor)));
  }
}
