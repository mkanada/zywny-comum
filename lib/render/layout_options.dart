/// The Verovio layout options exposed in the tuning panel, so combinations
/// can be tried against the same score.
///
/// Defaults, ranges and choice lists mirror `Toolkit::GetAvailableOptions()`
/// of the vendored Verovio; `test/layout_options_test.dart` checks the table
/// against the native library, so a Verovio bump that moves one of them
/// fails there instead of silently rendering something else.
library;

enum LayoutOptionKind { integer, decimal, toggle, choice }

/// One editable Verovio option. The value handed to Verovio is an `int`,
/// `double`, `bool` or `String` according to [kind].
class LayoutOption {
  const LayoutOption.integer(
    this.key,
    this.label, {
    required this.min,
    required this.max,
    required int this.defaultValue,
    this.softMax,
    this.tooltip,
    this.targets,
  }) : kind = LayoutOptionKind.integer,
       choices = const [];

  const LayoutOption.decimal(
    this.key,
    this.label, {
    required this.min,
    required this.max,
    required double this.defaultValue,
    this.tooltip,
  }) : kind = LayoutOptionKind.decimal,
       targets = null,
       softMax = null,
       choices = const [];

  const LayoutOption.toggle(
    this.key,
    this.label, {
    required bool this.defaultValue,
    this.tooltip,
  }) : kind = LayoutOptionKind.toggle,
       targets = null,
       min = 0,
       max = 0,
       softMax = null,
       choices = const [];

  const LayoutOption.choice(
    this.key,
    this.label, {
    required this.choices,
    required String this.defaultValue,
    this.tooltip,
  }) : kind = LayoutOptionKind.choice,
       targets = null,
       min = 0,
       max = 0,
       softMax = null;

  /// Verovio's option name, as in `--<key>` on the command line — or, when
  /// [targets] is set, the app's own name for an option that drives several.
  final String key;

  /// The Verovio options that receive this option's value, when it is not
  /// itself a Verovio option (one control for both margins of an axis).
  final List<String>? targets;

  /// Verovio option names this control writes to.
  List<String> get verovioKeys => targets ?? [key];
  final String label;
  final LayoutOptionKind kind;
  final num min;
  final num max;

  /// Upper end of the slider when Verovio's own range is too wide to be
  /// usable there (page size); values beyond it are still valid.
  final num? softMax;
  final List<String> choices;

  /// Verovio's own default.
  final Object defaultValue;
  final String? tooltip;
}

class LayoutGroup {
  const LayoutGroup(this.title, this.options);

  final String title;
  final List<LayoutOption> options;
}

/// Options that `lib/main.dart` sizes from the score box unless the user
/// turns that off; they travel as the request's page size, not as extras.
const kPageSizeKeys = {'pageWidth', 'pageHeight'};

const kLayoutGroups = <LayoutGroup>[
  LayoutGroup('Página', [
    LayoutOption.decimal(
      'unit',
      'Tamanho da notação (unit)',
      min: 4.5,
      max: 12,
      defaultValue: 9,
      tooltip:
          'Metade da distância entre as linhas da pauta. Maior = '
          'notação maior sobre a mesma página, com menos música em cada '
          'uma: refaz o layout. (O `scale` do Verovio só muda o tamanho '
          'de saída da página, como um zoom, e por isso não está aqui.)',
    ),
    LayoutOption.integer(
      'pageWidth',
      'Largura da página',
      min: 100,
      max: 100000,
      softMax: 10000,
      defaultValue: 2100,
      tooltip:
          'Décimos de milímetro (2100 = A4). Só vale com '
          '"Página acompanha a área" desligado.',
    ),
    LayoutOption.integer(
      'pageHeight',
      'Altura da página',
      min: 100,
      max: 60000,
      softMax: 6000,
      defaultValue: 2970,
      tooltip:
          'Décimos de milímetro (2970 = A4). Só vale com '
          '"Página acompanha a área" desligado.',
    ),
    LayoutOption.integer(
      'marginVertical',
      'Margem vertical',
      min: 0,
      max: 500,
      defaultValue: 50,
      targets: ['pageMarginTop', 'pageMarginBottom'],
    ),
    LayoutOption.integer(
      'marginHorizontal',
      'Margem horizontal',
      min: 0,
      max: 500,
      defaultValue: 50,
      targets: ['pageMarginLeft', 'pageMarginRight'],
    ),
    LayoutOption.toggle(
      'adjustPageHeight',
      'Ajustar altura ao conteúdo',
      defaultValue: false,
    ),
    LayoutOption.toggle(
      'adjustPageWidth',
      'Ajustar largura ao conteúdo',
      defaultValue: false,
    ),
    LayoutOption.choice(
      'header',
      'Cabeçalho',
      choices: ['none', 'auto', 'encoded'],
      defaultValue: 'auto',
    ),
    LayoutOption.choice(
      'footer',
      'Rodapé',
      choices: ['none', 'auto', 'encoded', 'always'],
      defaultValue: 'auto',
    ),
  ]),
  LayoutGroup('Quebras e sistemas', [
    LayoutOption.choice(
      'breaks',
      'Quebras',
      choices: ['none', 'auto', 'line', 'smart', 'encoded'],
      defaultValue: 'auto',
    ),
    LayoutOption.choice(
      'condense',
      'Condensar',
      choices: ['none', 'auto', 'encoded'],
      defaultValue: 'auto',
    ),
    LayoutOption.integer(
      'systemMaxPerPage',
      'Sistemas por página (máx.)',
      min: 0,
      max: 24,
      defaultValue: 0,
      tooltip: '0 = sem limite.',
    ),
    LayoutOption.choice(
      'systemDivider',
      'Divisor de sistema',
      choices: ['none', 'auto', 'left', 'left-right'],
      defaultValue: 'auto',
    ),
    LayoutOption.integer(
      'mnumInterval',
      'Numerar compassos a cada',
      min: 0,
      max: 64,
      defaultValue: 0,
      tooltip: '0 = não numera.',
    ),
  ]),
  LayoutGroup('Espaçamento', [
    LayoutOption.integer(
      'spacingStaff',
      'Entre pautas',
      min: 0,
      max: 48,
      defaultValue: 12,
    ),
    LayoutOption.integer(
      'spacingSystem',
      'Entre sistemas',
      min: 0,
      max: 48,
      defaultValue: 4,
    ),
    LayoutOption.decimal(
      'spacingLinear',
      'Linear',
      min: 0,
      max: 1,
      defaultValue: 0.25,
    ),
    LayoutOption.decimal(
      'spacingNonLinear',
      'Não linear',
      min: 0,
      max: 1,
      defaultValue: 0.6,
    ),
    LayoutOption.integer(
      'spacingBraceGroup',
      'Grupo de chave {',
      min: 0,
      max: 48,
      defaultValue: 12,
    ),
    LayoutOption.integer(
      'spacingBracketGroup',
      'Grupo de colchete [',
      min: 0,
      max: 48,
      defaultValue: 12,
    ),
  ]),
  LayoutGroup('Justificação', [
    LayoutOption.toggle(
      'justifyVertically',
      'Justificar na vertical',
      defaultValue: false,
    ),
    LayoutOption.toggle(
      'noJustification',
      'Sem justificação',
      defaultValue: false,
    ),
    LayoutOption.decimal(
      'justificationSystem',
      'Sistemas',
      min: 0,
      max: 10,
      defaultValue: 1,
    ),
    LayoutOption.decimal(
      'justificationStaff',
      'Pautas',
      min: 0,
      max: 10,
      defaultValue: 1,
    ),
    LayoutOption.decimal(
      'justificationMaxVertical',
      'Máx. vertical',
      min: 0,
      max: 1,
      defaultValue: 0.2,
    ),
    LayoutOption.decimal(
      'minLastJustification',
      'Último sistema (mín.)',
      min: 0,
      max: 1,
      defaultValue: 0.8,
      tooltip:
          'Fração da largura abaixo da qual o último sistema não é '
          'justificado.',
    ),
  ]),
  LayoutGroup('Notação', [
    LayoutOption.choice(
      'font',
      'Fonte musical',
      choices: ['Leipzig', 'Bravura', 'Gootville', 'Leland', 'Petaluma'],
      defaultValue: 'Leipzig',
    ),
    LayoutOption.decimal(
      'staffLineWidth',
      'Linha da pauta',
      min: 0.10,
      max: 0.30,
      defaultValue: 0.15,
    ),
    LayoutOption.decimal(
      'stemWidth',
      'Haste',
      min: 0.10,
      max: 0.50,
      defaultValue: 0.20,
    ),
    LayoutOption.decimal(
      'barLineWidth',
      'Barra de compasso',
      min: 0.10,
      max: 0.80,
      defaultValue: 0.30,
    ),
    LayoutOption.decimal(
      'slurCurveFactor',
      'Curvatura da ligadura',
      min: 0.2,
      max: 5,
      defaultValue: 1,
    ),
    LayoutOption.integer(
      'beamMaxSlope',
      'Inclinação máx. da viga',
      min: 0,
      max: 20,
      defaultValue: 10,
    ),
    LayoutOption.toggle(
      'beamFrenchStyle',
      'Vigas estilo francês',
      defaultValue: false,
    ),
    LayoutOption.decimal(
      'hairpinSize',
      'Tamanho do hairpin',
      min: 1,
      max: 8,
      defaultValue: 3,
    ),
    LayoutOption.decimal(
      'lyricSize',
      'Tamanho da letra',
      min: 2,
      max: 8,
      defaultValue: 4.5,
    ),
    LayoutOption.choice(
      'multiRestStyle',
      'Pausas de vários compassos',
      choices: ['auto', 'default', 'block', 'symbols'],
      defaultValue: 'auto',
    ),
    LayoutOption.choice(
      'pedalStyle',
      'Estilo do pedal',
      choices: ['auto', 'line', 'pedstar', 'altpedstar'],
      defaultValue: 'auto',
    ),
  ]),
];

/// Values the app starts from: Verovio's defaults, except where the app has
/// always deviated. The footer would take a strip off the bottom of every
/// page, shrinking the usable notation area; a `unit` of 4.5 (the smallest
/// the panel allows) fits more music on a desktop-sized page.
const kAppDefaults = <String, Object>{'footer': 'none', 'unit': 4.5};

/// The options that differ from Verovio's own defaults — all it takes to
/// reproduce a render, e.g. as `verovio --<key> <value>`.
///
/// [kPageSizeKeys] are left out: the page size travels separately, since the
/// app usually derives it from the score box.
Map<String, Object> layoutOptionsToSend(Map<String, Object> values) {
  final out = <String, Object>{};
  for (final group in kLayoutGroups) {
    for (final option in group.options) {
      if (kPageSizeKeys.contains(option.key)) continue;
      final value = values[option.key];
      if (value != null && value != option.defaultValue) {
        for (final key in option.verovioKeys) {
          out[key] = value;
        }
      }
    }
  }
  return out;
}

/// `unit` que o app usa por padrão no celular (Android/iOS): a tela é
/// pequena e a partitura é lida de longe, então a notação começa grande. O
/// painel de layout continua livre para mudar.
const double kPhoneUnit = 12;

/// Verovio's defaults with [kAppDefaults] applied — and, with [phone],
/// [kPhoneUnit] as the notation size.
Map<String, Object> initialLayoutValues({bool phone = false}) => {
  for (final group in kLayoutGroups)
    for (final option in group.options) option.key: option.defaultValue,
  ...kAppDefaults,
  if (phone) 'unit': kPhoneUnit,
};
