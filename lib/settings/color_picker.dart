// Seletor de cor das configurações: uma paleta larga para o toque rápido e
// o ajuste fino (matiz, saturação, brilho, código) para qualquer cor. Feito
// aqui, sem pacote de color picker, porque são três controles deslizantes e
// uma grade.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zywny_bloc/zywny_bloc.dart';

import 'color_picker_cubit.dart';

/// Matizes das colunas da paleta, em graus.
const List<double> _kPaletteHues = [0, 25, 45, 130, 175, 210, 265, 320];

/// (saturação, brilho) de cada linha da paleta: do vivo claro ao escuro.
/// Nada de tom pastel — a cor pinta nota fina sobre papel branco.
const List<(double, double)> _kPaletteTones = [
  (0.60, 0.98),
  (0.85, 0.90),
  (0.90, 0.72),
  (0.95, 0.52),
];

/// Linha de neutros (pretos, cinzas e marrons).
const List<Color> _kPaletteNeutrals = [
  Color(0xFF000000),
  Color(0xFF37474F),
  Color(0xFF607D8B),
  Color(0xFF8E8E93),
  Color(0xFF3E2723),
  Color(0xFF5D4037),
  Color(0xFF8D6E63),
  Color(0xFFC07A00),
];

/// A paleta do seletor, linha a linha ([_kPaletteHues] colunas).
final List<Color> kColorPalette = [
  for (final (s, v) in _kPaletteTones)
    for (final h in _kPaletteHues) HSVColor.fromAHSV(1, h, s, v).toColor(),
  ..._kPaletteNeutrals,
];

/// `#RRGGBB` de [color].
String colorHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Abre o seletor para [initial]; devolve a cor escolhida, ou `null` se o
/// usuário cancelou. [defaultColor] é o que "Padrão" repõe.
Future<Color?> showColorPicker(
  BuildContext context, {
  required String title,
  required Color initial,
  required Color defaultColor,
}) => showDialog<Color>(
  context: context,
  builder: (_) => ColorPickerDialog(
    title: title,
    initial: initial,
    defaultColor: defaultColor,
  ),
);

class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({
    super.key,
    required this.title,
    required this.initial,
    required this.defaultColor,
  });

  final String title;
  final Color initial;
  final Color defaultColor;

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  // Dono do campo do código: fica aqui (e não no cubit) para o texto que se
  // digita sobreviver à troca de layout (celular deitado), como antes.
  late final TextEditingController _hex = TextEditingController(
    text: colorHex(widget.initial).substring(1),
  );

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ColorPickerCubit(initial: widget.initial),
      child: BlocListener<ColorPickerCubit, ColorPickerState>(
        // Uma escolha pela paleta ou pelo ajuste põe o código da cor no campo
        // (o serial sobe mesmo com a cor igual). O que se digita não sobe o
        // serial: o campo fica como foi digitado.
        listenWhen: (antes, depois) => antes.serial != depois.serial,
        listener: (_, state) {
          _hex.text = colorHex(state.color).substring(1);
        },
        child: BlocBuilder<ColorPickerCubit, ColorPickerState>(
          builder: (context, state) {
            final theme = Theme.of(context);
            final size = MediaQuery.sizeOf(context);
            // Celular deitado: pouca altura e muita largura — paleta e ajuste
            // fino ficam lado a lado em vez de empilhados.
            final wide = size.width >= 600 && size.height < 560;
            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 660 : 380),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _titleRow(theme, state.color),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: _body(context, wide, state),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buttons(context),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// O título e a prévia da nota, antes e depois da escolha.
  Widget _titleRow(ThemeData theme, Color color) => Row(
    children: [
      Expanded(child: Text(widget.title, style: theme.textTheme.titleMedium)),
      _NotePreview(before: widget.initial, after: color),
    ],
  );

  /// A paleta e o ajuste fino: lado a lado (celular deitado) ou empilhados.
  Widget _body(BuildContext context, bool wide, ColorPickerState state) {
    final cubit = context.read<ColorPickerCubit>();
    final palette = _Palette(value: state.color, onPick: cubit.escolher);
    final fine = _FineTuning(
      hsv: state.hsv,
      hex: _hex,
      onChanged: cubit.ajustar,
      onHexChanged: cubit.digitar,
    );
    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: palette),
              const SizedBox(width: 20),
              Expanded(child: fine),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [palette, const SizedBox(height: 12), fine],
          );
  }

  /// Padrão à esquerda; cancelar e aplicar à direita. `Wrap`, não `Row`: em
  /// tela estreita com fonte grande os botões descem uma linha em vez de
  /// estourar.
  Widget _buttons(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton(
        onPressed: () =>
            context.read<ColorPickerCubit>().escolher(widget.defaultColor),
        child: const Text('Padrão'),
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () =>
                Navigator.of(context)
                    .pop(context.read<ColorPickerCubit>().state.color),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    ],
  );
}

/// A grade de [kColorPalette]; a cor atual, se estiver nela, fica marcada.
class _Palette extends StatelessWidget {
  const _Palette({required this.value, required this.onPick});

  final Color value;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: _kPaletteHues.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (final c in kColorPalette)
          _PaletteCell(
            color: c,
            selected: c.toARGB32() == value.toARGB32(),
            onTap: () => onPick(c),
          ),
      ],
    );
  }
}

class _PaletteCell extends StatelessWidget {
  const _PaletteCell({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: selected
            ? BorderSide(
                color: Theme.of(context).colorScheme.onSurface,
                width: 2.5,
              )
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: selected
            ? Icon(Icons.check, size: 18, color: _inkOn(color))
            : null,
      ),
    );
  }
}

Color _inkOn(Color color) =>
    color.computeLuminance() > 0.5 ? Colors.black : Colors.white;

/// Matiz, saturação e brilho em controles deslizantes, mais o código
/// `#RRGGBB` para digitar ou colar.
class _FineTuning extends StatelessWidget {
  const _FineTuning({
    required this.hsv,
    required this.hex,
    required this.onChanged,
    required this.onHexChanged,
  });

  final HSVColor hsv;
  final TextEditingController hex;
  final ValueChanged<HSVColor> onChanged;
  final ValueChanged<String> onHexChanged;

  @override
  Widget build(BuildContext context) {
    final h = hsv.hue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GradientSlider(
          label: 'Matiz',
          value: h,
          max: 360,
          colors: [
            for (var d = 0.0; d <= 360; d += 60)
              HSVColor.fromAHSV(1, d % 360, 1, 1).toColor(),
          ],
          // 360° é o mesmo vermelho de 0°, mas `HSVColor` só aceita < 360.
          onChanged: (v) => onChanged(hsv.withHue(v >= 360 ? 359.9 : v)),
        ),
        _GradientSlider(
          label: 'Saturação',
          value: hsv.saturation,
          max: 1,
          colors: [
            HSVColor.fromAHSV(1, h, 0, hsv.value).toColor(),
            HSVColor.fromAHSV(1, h, 1, hsv.value).toColor(),
          ],
          onChanged: (v) => onChanged(hsv.withSaturation(v)),
        ),
        _GradientSlider(
          label: 'Brilho',
          value: hsv.value,
          max: 1,
          colors: [
            Colors.black,
            HSVColor.fromAHSV(1, h, hsv.saturation, 1).toColor(),
          ],
          onChanged: (v) => onChanged(hsv.withValue(v)),
        ),
        const SizedBox(height: 4),
        _hexField(context),
      ],
    );
  }

  /// O código hexadecimal da cor, digitado (seis dígitos, sem o #).
  Widget _hexField(BuildContext context) => Row(
    children: [
      Text('Código', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(width: 12),
      SizedBox(
        width: 120,
        child: TextField(
          controller: hex,
          onChanged: onHexChanged,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
          ],
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(
            isDense: true,
            prefixText: '#',
            counterText: '',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    ],
  );
}

/// Um `Slider` cujo trilho é o próprio gradiente do que ele muda.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.colors,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  // Raio do halo do polegar: o `Slider` recua o trilho disto em cada ponta,
  // e a faixa do gradiente acompanha.
  static const double _overlayRadius = 16;
  static const double _barHeight = 14;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        SizedBox(
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _overlayRadius - _barHeight / 2,
                ),
                child: Container(
                  height: _barHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_barHeight / 2),
                    border: Border.all(color: Colors.black26),
                    gradient: LinearGradient(colors: colors),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: _barHeight,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayColor: Colors.black12,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 10,
                    elevation: 3,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: _overlayRadius,
                  ),
                ),
                child: Slider(
                  value: value.clamp(0, max),
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A cor de antes e a de agora como duas notas numa pauta em papel branco —
/// é assim que ela vai aparecer.
class _NotePreview extends StatelessWidget {
  const _NotePreview({required this.before, required this.after});

  final Color before;
  final Color after;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black26),
      ),
      child: CustomPaint(painter: _NotePreviewPainter(before, after)),
    );
  }
}

class _NotePreviewPainter extends CustomPainter {
  const _NotePreviewPainter(this.before, this.after);

  final Color before;
  final Color after;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 6.0;
    final top = (size.height - 4 * gap) / 2;
    final line = Paint()
      ..color = Colors.black54
      ..strokeWidth = 0.8;
    for (var i = 0; i < 5; i++) {
      final y = top + i * gap;
      canvas.drawLine(Offset(6, y), Offset(size.width - 6, y), line);
    }
    void note(double x, double y, Color color) {
      final paint = Paint()..color = color;
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(-0.35)
        ..drawOval(
          Rect.fromCenter(center: Offset.zero, width: gap * 1.5, height: gap),
          paint,
        )
        ..restore()
        ..drawLine(
          Offset(x + gap * 0.68, y - 1),
          Offset(x + gap * 0.68, y - gap * 3.2),
          paint..strokeWidth = 1.3,
        );
    }

    // Antes num espaço, agora na linha de baixo dele: as duas cabeças não
    // se confundem e a de agora fica à direita, onde o olho termina.
    note(size.width * 0.33, top + 2.5 * gap, before);
    note(size.width * 0.67, top + 3 * gap, after);
  }

  @override
  bool shouldRepaint(_NotePreviewPainter old) =>
      old.before != before || old.after != after;
}
