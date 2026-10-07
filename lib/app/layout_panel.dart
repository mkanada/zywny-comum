import 'package:flutter/material.dart';

import '../render/layout_options.dart';

import 'package:zywny_library/library_term_scope.dart';

/// Floating panel with what belongs to **one piece**: the Verovio options of
/// [kLayoutGroups] (notation size first) and the on-screen zoom. Each piece
/// keeps its own values (`PieceSettingsStore`); what holds for every piece —
/// sound, MIDI, colors — lives in `GeneralSettingsPanel`.
///
/// It only edits [values]; `lib/main.dart` owns them and does the render.
/// Sliders report every step through [onChanged] and ask for the render once,
/// on release, through [onCommit]; toggles and choices do both at once. Zoom
/// is a pure paint-time setting and applies immediately — it never reaches
/// Verovio, so there's nothing to render.
class LayoutPanel extends StatelessWidget {
  const LayoutPanel({
    super.key,
    required this.values,
    required this.pageFitsBox,
    required this.fittedPage,
    required this.onChanged,
    required this.onCommit,
    required this.onFitChanged,
    required this.onReset,
    required this.onCopy,
    required this.onClose,
    this.zoomSection,
    this.subtitle,
  });

  /// Which piece these options belong to ("12 · Vinde, Povo do Senhor").
  final String? subtitle;

  final Map<String, Object> values;

  /// Whether the page size follows the score area instead of the
  /// `pageWidth`/`pageHeight` values.
  final bool pageFitsBox;

  /// Page size the score area asks for, in tenths of a millimetre; null
  /// before the first layout.
  final Size? fittedPage;

  final void Function(String key, Object value) onChanged;
  final VoidCallback onCommit;
  final ValueChanged<bool> onFitChanged;
  final VoidCallback onReset;
  final VoidCallback onCopy;
  final VoidCallback onClose;

  /// The on-screen zoom row (built in `lib/main.dart`, which owns the
  /// `TransformationController`); embedded here instead of floating over
  /// the score. `null` on the phone, where the score is not zoomable.
  final Widget? zoomSection;

  @override
  Widget build(BuildContext context) {
    final term = LibraryTermScope.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ajustes da partitura',
                        style: theme.textTheme.titleSmall,
                      ),
                      if (subtitle case final subtitle?)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar opções (JSON)',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_all, size: 20),
                ),
                IconButton(
                  tooltip:
                      'Restaurar o layout padrão ${term.neste} ${term.singular}',
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt, size: 20),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                if (zoomSection case final zoom?) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text('Zoom', style: theme.textTheme.labelLarge),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: zoom,
                  ),
                ],
                SwitchListTile(
                  dense: true,
                  title: const Text('Página acompanha a área'),
                  subtitle: Text(_fitSubtitle()),
                  value: pageFitsBox,
                  onChanged: onFitChanged,
                ),
                for (final group in kLayoutGroups)
                  ExpansionTile(
                    key: PageStorageKey<String>(group.title),
                    initiallyExpanded: group == kLayoutGroups.first,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    dense: true,
                    title: Text(group.title, style: theme.textTheme.labelLarge),
                    children: [
                      for (final option in group.options)
                        _OptionRow(
                          option: option,
                          value: _shownValue(option),
                          enabled:
                              !(pageFitsBox &&
                                  kPageSizeKeys.contains(option.key)),
                          onChanged: onChanged,
                          onCommit: onCommit,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fitSubtitle() {
    final page = fittedPage;
    if (!pageFitsBox) return 'usa a largura e a altura abaixo';
    if (page == null) return 'aguardando o primeiro layout';
    return '${page.width.round()}×${page.height.round()} '
        '(${(page.width / 10).round()}×${(page.height / 10).round()} mm)';
  }

  /// While the page follows the score area the size sliders show what is
  /// actually used, not the stale manual value.
  Object _shownValue(LayoutOption option) {
    final page = fittedPage;
    if (pageFitsBox && page != null) {
      if (option.key == 'pageWidth') return page.width.round();
      if (option.key == 'pageHeight') return page.height.round();
    }
    return values[option.key] ?? option.defaultValue;
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onCommit,
  });

  final LayoutOption option;
  final Object value;
  final bool enabled;
  final void Function(String key, Object value) onChanged;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modified = value != option.defaultValue;
    final style = theme.textTheme.bodySmall!.copyWith(
      color: modified ? theme.colorScheme.primary : null,
      fontWeight: modified ? FontWeight.w600 : null,
    );

    Widget label(Widget trailing) {
      Widget text = Text(option.label, style: style);
      if (option.tooltip != null) {
        text = Tooltip(message: option.tooltip!, child: text);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: text),
            trailing,
          ],
        ),
      );
    }

    switch (option.kind) {
      case LayoutOptionKind.toggle:
        return SwitchListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(option.label, style: style),
          value: value as bool,
          onChanged: (v) {
            onChanged(option.key, v);
            onCommit();
          },
        );
      case LayoutOptionKind.choice:
        return label(
          DropdownButton<String>(
            isDense: true,
            value: value as String,
            style: style.copyWith(color: theme.colorScheme.onSurface),
            items: [
              for (final c in option.choices)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) {
              if (v == null) return;
              onChanged(option.key, v);
              onCommit();
            },
          ),
        );
      case LayoutOptionKind.integer:
      case LayoutOptionKind.decimal:
        final isInt = option.kind == LayoutOptionKind.integer;
        // Decimals: hundredths for the 0–1 style ranges, tenths otherwise.
        final decimals = isInt ? 0 : (option.max - option.min <= 1.5 ? 2 : 1);
        final step = isInt ? 1.0 : (decimals == 2 ? 0.01 : 0.1);
        final lo = option.min.toDouble();
        final hi = (option.softMax ?? option.max).toDouble();
        final steps = ((hi - lo) / step).round();
        final number = (value as num).toDouble();
        return Column(
          children: [
            label(
              Text(
                isInt ? '${number.round()}' : number.toStringAsFixed(decimals),
                style: style,
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: number.clamp(lo, hi),
                min: lo,
                max: hi,
                divisions: steps <= 1000 ? steps : null,
                onChanged: enabled
                    ? (v) => onChanged(
                        option.key,
                        isInt
                            ? v.round()
                            : double.parse(v.toStringAsFixed(decimals)),
                      )
                    : null,
                onChangeEnd: enabled ? (_) => onCommit() : null,
              ),
            ),
          ],
        );
    }
  }
}
